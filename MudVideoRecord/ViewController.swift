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
        self.view.backgroundColor = UIColor.whiteColor()
        let button =  UIButton(type: UIButtonType.Custom)
        button.frame = CGRectMake(0,0,100, 100)
        button.setImage(UIImage(named: "MudVideoRecord.bundle/camera"), forState: UIControlState.Normal)
        button.addTarget(self, action: "buttonAction:", forControlEvents: UIControlEvents.TouchUpInside)
        button.center = CGPointMake(CGRectGetWidth(self.view.frame)/2, CGRectGetHeight(self.view.frame)/2)
        self.view.addSubview(button)
    }
    
    func buttonAction(sender: AnyObject?) {
        let recordVC = MudVideoRecordViewController()
        self.presentViewController(recordVC, animated: true) { () -> Void in
            
        }
    }


}

