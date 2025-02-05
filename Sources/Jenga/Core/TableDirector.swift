import UIKit

public class TableDirector: NSObject {
    
    public let tableView: UITableView
    
    public private(set) weak var delegate: UIScrollViewDelegate?
    
    private(set) var rowHeightCalculator: RowHeightCalculator
    
    private var cellRegisterer: TableCellRegisterer?
    
    private var sections: [Section] = [] {
        didSet { tableView.reloadData() }
    }
    
    public var isEmpty: Bool { sections.isEmpty }
    
    public init(_ tableView: UITableView,
                delegate: UIScrollViewDelegate? = .none,
                isRegisterCell: Bool = true,
                rowheightCalculator: RowHeightCalculator) {
        self.tableView = tableView
        self.delegate = delegate
        self.rowHeightCalculator = rowheightCalculator
        if isRegisterCell {
            self.cellRegisterer = TableCellRegisterer(tableView: tableView)
        }
        super.init()
        
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: String(describing: UITableViewCell.self))
    }
    
    public convenience init(_ tableView: UITableView,
                            delegate: UIScrollViewDelegate? = .none,
                            isRegisterCell: Bool = true) {
        self.init(tableView,
                  delegate: delegate,
                  isRegisterCell: isRegisterCell,
                  rowheightCalculator: TableCellHeightCalculator(tableView: tableView)
        )
    }
    
    private var tableBody: [Table]?
    public func setup(_ tableBody: [Table]) {
        self.tableBody = tableBody
        let sections = assemble(with: tableBody)
        self.sections = sections.filter { !($0.isEmpty && $0.hiddenWithEmpty) }
        reload()
        
        weak var `self` = self
        func reloadAll() {
            self?.setup(self?.tableBody ?? [])
        }
        
        func reloadSection(_ section: Section) {
            guard let self = self else { return }
            guard let index = self.sections.firstIndex(where: { $0.hashValue == section.hashValue }) else { return }
            UIView.performWithoutAnimation {
                self.tableView.reloadSections(IndexSet(integer: index), with: .none)
            }
        }
        
        sections.forEach {
            guard let section = $0 as? TableSection  else { return }
            let old = section.isEmpty && section.hiddenWithEmpty
            section.didUpdate = { section in
                let new = section.isEmpty && section.hiddenWithEmpty
                old == new ? reloadSection(section) : reloadAll()
            }
        }
    }
    
    public func reload() {
        tableView.reloadData()
    }
    
    public override func responds(to selector: Selector) -> Bool {
        return super.responds(to: selector) || delegate?.responds(to: selector) == true
    }
    
    public override func forwardingTarget(for selector: Selector) -> Any? {
        return delegate?.responds(to: selector) == true ? delegate : super.forwardingTarget(for: selector)
    }
    
    deinit { log("deinit", classForCoder) }
}

extension TableDirector {
    
    private func assemble(with tableBody: [Table]) -> [Section] {
        var result: [Section] = []
        var section: BrickSection?
        
        func close() {
            guard let temp = section else { return }
            result.append(temp)
            section = nil
        }
        
        for (index, body) in tableBody.enumerated() {
            switch body {
            case let body as Section:
                close()
                result.append(body)
                
            case let body as Header:
                close()
                section = BrickSection()
                section?.header = body.content
                section?.rowHeight = body.rowHeight
                section?.hiddenWithEmpty = body.hiddenWithEmpty
                
            case let body as Footer:
                section = section ?? BrickSection()
                section?.footer = body.content
                section?.rowHeight = body.rowHeight
                section?.hiddenWithEmpty = body.hiddenWithEmpty
                close()
                
            case let body as Row:
                section = section ?? BrickSection()
                section?.append(body)
                
                if index == tableBody.count - 1 {
                    close()
                }
                
            case let body as Spacer:
                section = section ?? BrickSection()
                section?.append(SpacerRow(body.height, color: body.color))
                if index == tableBody.count - 1 {
                    close()
                }
                
            default:
                break
            }
        }
        return result
    }
}

extension TableDirector: UITableViewDataSource {
    
    public func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].numberOfRows
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        func cell(for row: Row) -> UITableViewCell {
            if let row = row as? SystemRow {
                let cell =
                tableView.dequeueReusableCell(withIdentifier: row.reuseIdentifier) ??
                row.cellType.init(style: row.cellStyle, reuseIdentifier: row.reuseIdentifier)
                (row as? RowConfigurable)?.configure(cell)
                cell.selectionStyle = row.selectionStyle
                return cell
                
            } else {
                cellRegisterer?.register(cellType: row.cellType, forCellReuseIdentifier: row.reuseIdentifier)
                
                let cell =
                tableView.dequeueReusableCell(withIdentifier: row.reuseIdentifier, for: indexPath)
                (row as? RowConfigurable)?.configure(cell)
                cell.selectionStyle = row.selectionStyle
                return cell
            }
        }
        
        let section = sections[indexPath.section]
        let row = section.rows[indexPath.row]
        return cell(for: row)
    }
}

extension TableDirector: UITableViewDelegate {
    
    public func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let row = sections[safe: indexPath.section]?.rows[safe: indexPath.row]
        (row as? RowConfigurable)?.recovery(cell)
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let section = sections[indexPath.section]
        let row = section.rows[indexPath.row]
        
        switch (section, row) {
        case let (radio as RadioSection, option as OptionRowCompatible):
            let changes: [IndexPath] = radio.toggle(option).map {
                IndexPath(row: $0, section: indexPath.section)
            }
            if changes.isEmpty {
                tableView.deselectRow(at: indexPath, animated: false)
            } else {
                tableView.reloadRows(at: changes, with: .automatic)
            }
            
        case let (_, option as OptionRowCompatible):
            option.isSelected = !option.isSelected
            tableView.reloadData()
            
        case (_, is TapActionRowCompatible):
            tableView.deselectRow(at: indexPath, animated: true)
            DispatchQueue.main.async {
                row.action?()
            }
            
        case let (_, row) where row.isSelectable:
            DispatchQueue.main.async {
                row.action?()
            }
            
        default:
            break
        }
    }
    
    public func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        let section = sections[indexPath.section]
        let row = section.rows[indexPath.row]
        
        if !(row is SystemRow) {
            cellRegisterer?.register(cellType: row.cellType, forCellReuseIdentifier: row.reuseIdentifier)
        }
        
        var calculatorHeight: CGFloat? = nil
        let isCalculator = (row.estimatedHeight?.isHighAutomaticDimension ?? false)
        || (row.estimatedHeight == nil && (row.height?.isHighAutomaticDimension ?? false))
        || (row.estimatedHeight == nil && row.height == nil && (section.rowHeight?.isHighAutomaticDimension ?? false))
        
        if isCalculator {
            calculatorHeight = rowHeightCalculator.estimatedHeight(forRow: row, at: indexPath)
        }
        
        return calculatorHeight.nonEfficient
        ?? (row.estimatedHeight?.value).nonEfficient
        ?? (row.height?.value).nonEfficient
        ?? (section.rowHeight?.value).nonEfficient
        ?? UITableView.automaticDimension
    }
    
    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let section = sections[indexPath.section]
        let row = section.rows[indexPath.row]
        
        if !(row is SystemRow) {
            cellRegisterer?.register(cellType: row.cellType, forCellReuseIdentifier: row.reuseIdentifier)
        }
        var calculatorHeight: CGFloat? = nil
        let isCalculator = (row.height?.isHighAutomaticDimension ?? false)
        || (row.height == nil && (section.rowHeight?.isHighAutomaticDimension ?? false))
        
        if isCalculator {
            calculatorHeight = rowHeightCalculator.height(forRow: row, at: indexPath)
        }
        return calculatorHeight.nonEfficient
        ?? (row.height?.value).nonEfficient
        ?? (section.rowHeight?.value).nonEfficient
        ?? UITableView.automaticDimension
    }
    
    public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let header = sections[section].header
        return header.height
        ?? header.view?.frame.size.height
        ?? UITableView.automaticDimension
    }
    
    public func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        let footer = sections[section].footer
        return footer.height
        ?? footer.view?.frame.size.height
        ?? UITableView.automaticDimension
    }
    
    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sections[section].header.title
    }
    
    public func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return sections[section].footer.title
    }
    
    public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return sections[section].header.view
    }
    
    public func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return sections[section].footer.view
    }
    
    // MARK: - UITableViewDelegate
    
    public func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return sections[indexPath.section].rows[indexPath.row].isSelectable
    }
    
    public func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        let row = sections[indexPath.section].rows[indexPath.row]
        switch row {
        case let navigation as NavigationRowCompatible:
            DispatchQueue.main.async {
                navigation.accessoryButtonAction?()
            }
            
        default:
            break
        }
    }
}
