//
//  ViewController.swift
//  MudVideoRecord
//
//  Created by TimTiger on 16/1/19.
//  Copyright © 2016年 Mudmen. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        let controller = MudVideoRecordViewController()
        self.presentViewController(controller, animated: true) { () -> Void in
            
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

