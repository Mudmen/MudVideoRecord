//
//  MudVideoPreviewView.swift
//  MudVideoRecord
//
//  Created by TimTiger on 16/1/19.
//  Copyright © 2016年 Mudmen. All rights reserved.
//

import UIKit
import AVFoundation

class MudVideoPreviewView: UIView {
    
    override class func layerClass()->AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    var session: AVCaptureSession! {
        didSet {
            (self.layer as! AVCaptureVideoPreviewLayer).session = session
        }
    }
    
}
