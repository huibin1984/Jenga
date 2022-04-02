//
//  CustomViewController.swift
//  TableKit
//
//  Created by 方林威 on 2022/3/29.
//

import UIKit
import Jenga

class CustomViewController: BaseViewController, DSLAutoTable {
    
    override var pageTitle: String { get { "自定义Cell" } }
    
    // DSL
    @TableBuilder
    var tableContents: [Section] {
        
        TableSection {
            
            TableRow<BannerCell>("image1")
                .height(1184 / 2256 * (UIScreen.main.bounds.width - 32))
                .customize { [weak self] cell in
                    cell.delegate = self
                }
            
            SpacerRow(10)
            
            TableRow<BannerCell>()
                .height(1540 / 2078 * (UIScreen.main.bounds.width - 32))
                .data("image2")
                .customize { (cell, value) in
                    print(cell, value)
                }
        }
        .headerHeight(20)
    }
}


extension CustomViewController: BannerCellDelegate {
    
    func bannerOpenAction() {
        UIApplication.shared.open(URL(string: "https://github.com/fanglinwei/TableKit")!)
    }
}

