//
//  MudVideoControls.swift
//  MudVideoRecord
//
//  Created by TimTiger on 16/1/19.
//  Copyright © 2016年 Mudmen. All rights reserved.
//

import UIKit
import AVFoundation
import Foundation

protocol MudVideoControlsDelegate: NSObjectProtocol {
    func videoControls(controls: MudVideoControls,startOrPauseDidSelected sendr: AnyObject?)
    func videoControls(controls: MudVideoControls,finishDidSelected sendr: AnyObject?)
    func videoControls(controls: MudVideoControls,cancelDidSelected sendr: AnyObject?)
    func videoControls(controls: MudVideoControls,deleteDidSelected sendr: AnyObject?)
    func videoControls(controls: MudVideoControls,cameraChangeDidSelected sendr: AnyObject?)
    func videoControls(controls: MudVideoControls,flashModeChangeDidSelected sendr: AnyObject?)
    func videoControls(controls: MudVideoControls,focusChangeDidSelected sender: UITapGestureRecognizer)
}

class MudVideoControls: UIView {

    weak var delegate: MudVideoControlsDelegate?
    
    var maxSeconds = 3000
    var minSeconds = 60
    
    /*!
    @property recordButton
    @abstract 录制按钮
    */
    var recordButton: UIButton!
    
    /*!
    @property finishButton
    @abstract 录制完成按钮
    */
    var finishButton: UIButton!

    /*!
    @property finishButton
    @abstract 删除已录制的部分
    */
    var deleteButton: UIButton!
    
    /*!
    @property cancelButton
    @abstract 取消录制
    */
    var cancelButton: UIButton!
    
    /*!
    @property cameraChangeButton
    @abstract 摄像头切换按钮
    */
    var cameraChangeButton: UIButton!
    
    /*!
    @property flashModeChangeButton
    @abstract 闪光灯模式切换按钮
    */
    var flashModeChangeButton: UIButton!
    
    /*!
    @property recordTimeLabel
    @abstract 拍摄时长显示
    */
    var recordTimeLabel: UIButton!
    
    /*!
    @property progressView
    @abstract 拍摄进度
    */
    var progressView: UIProgressView!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setupView()
        //设置自动布局
        self.setupLayoutConstraint()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    private func setupView() {
        self.backgroundColor = UIColor.clearColor()
        
        let bottomHeight = self.bounds.size.height-64-self.bounds.size.width*0.75
        
        let whiteTopView = UIView(frame: CGRectMake(0,0,self.bounds.size.width,64))
        whiteTopView.backgroundColor = UIColor.whiteColor()
        whiteTopView.alpha = 0.5
        whiteTopView.userInteractionEnabled = false
        self.addSubview(whiteTopView)
        
        let whiteBottomView = UIView(frame: CGRectMake(0,64+self.bounds.size.width*0.75,self.bounds.size.width,bottomHeight))
        whiteBottomView.backgroundColor = UIColor.whiteColor()
        whiteBottomView.alpha = 0.5
        whiteBottomView.userInteractionEnabled = false
        self.addSubview(whiteBottomView)
        
        self.cancelButton = UIButton(type: UIButtonType.Custom)
        self.cancelButton.setTitle("取消", forState: UIControlState.Normal)
        self.cancelButton.frame = CGRectMake(0, 20, 100, 44)
        self.cancelButton.titleLabel?.font = UIFont.systemFontOfSize(17)
        self.cancelButton.contentHorizontalAlignment = UIControlContentHorizontalAlignment.Left
        self.cancelButton.titleLabel?.textAlignment = NSTextAlignment.Left
        self.cancelButton.addTarget(self, action: "buttonAction:", forControlEvents: UIControlEvents.TouchUpInside)
        self.cancelButton.titleEdgeInsets = UIEdgeInsetsMake(0,10,0,0)
        self.cancelButton.setTitleColor(UIColor(red: 70.0/255, green: 79.0/255, blue: 84.0/255, alpha: 1), forState: UIControlState.Normal)
        self.addSubview(self.cancelButton)
        
        self.cameraChangeButton = UIButton(type: UIButtonType.Custom)
        self.cameraChangeButton.frame = CGRectMake(self.bounds.size.width-55-48, 20, 55, 44)
        self.cameraChangeButton.addTarget(self, action: "buttonAction:", forControlEvents: UIControlEvents.TouchUpInside)
        self.cameraChangeButton.setImage(UIImage(named: "MudVideoRecord.bundle/camera"), forState: UIControlState.Normal)
        self.addSubview(self.cameraChangeButton)
        
        self.flashModeChangeButton = UIButton(type: UIButtonType.Custom)
        self.flashModeChangeButton.frame = CGRectMake(self.bounds.size.width-48, 20, 48, 44)
        self.flashModeChangeButton.addTarget(self, action: "buttonAction:", forControlEvents: UIControlEvents.TouchUpInside)
        self.flashModeChangeButton.setImage(UIImage(named: "MudVideoRecord.bundle/flash_close"), forState: UIControlState.Normal)
        self.addSubview(self.flashModeChangeButton)
        
        self.recordTimeLabel = UIButton(type: UIButtonType.Custom)
        self.recordTimeLabel.setBackgroundImage(UIImage(named: "MudVideoRecord.bundle/timebg.png")?.stretchableImageWithLeftCapWidth(15, topCapHeight: 7), forState: UIControlState.Normal)
        self.recordTimeLabel.setTitleColor(UIColor.lightGrayColor(), forState: UIControlState.Normal)
        self.recordTimeLabel.titleLabel?.font = UIFont.systemFontOfSize(12)
        self.recordTimeLabel.frame =  CGRectMake(0, 0, 50, 20)
        self.recordTimeLabel.center = CGPointMake(self.bounds.size.width-32.5, 64+self.bounds.size.width*0.75+3+20)
        self.recordTimeLabel.setTitle(String(format: "%0.1f秒",0), forState: UIControlState.Normal)
        self.addSubview(self.recordTimeLabel)
        
        self.recordButton = UIButton(type: UIButtonType.Custom)
        self.recordButton.setImage(UIImage(named: "MudVideoRecord.bundle/record_normal"), forState: UIControlState.Normal)
        self.recordButton.setImage(UIImage(named: "MudVideoRecord.bundle/record_normal"), forState: UIControlState.Highlighted)
        self.recordButton.setTitleColor(UIColor.grayColor(), forState: UIControlState.Normal)
        self.recordButton.frame =  CGRectMake(0, 0, 90, 90)
        self.recordButton.addTarget(self, action: "buttonAction:", forControlEvents: UIControlEvents.TouchUpInside)
//        self.recordButton.addTarget(self, action: "buttonAction:", forContrsolEvents: UIControlEvents.TouchDown)
        self.recordButton.center = CGPointMake(self.bounds.size.width/2, self.bounds.size.height-bottomHeight/2)
        self.addSubview(self.recordButton)
        
        self.finishButton = UIButton(type: UIButtonType.Custom)
        self.finishButton.setImage(UIImage(named: "MudVideoRecord.bundle/finish"), forState: UIControlState.Normal)
        self.finishButton.setTitleColor(UIColor.grayColor(), forState: UIControlState.Normal)
        self.finishButton.frame =  CGRectMake(CGRectGetMaxX(self.recordButton.frame), 0, 45, 45)
        self.finishButton.addTarget(self, action: "buttonAction:", forControlEvents: UIControlEvents.TouchUpInside)
        self.finishButton.center = CGPointMake(self.bounds.size.width-22.5-37, self.bounds.size.height-bottomHeight/2)
        self.addSubview(self.finishButton)
        
        self.deleteButton = UIButton(type: UIButtonType.Custom)
        self.deleteButton.frame = CGRectMake(0, 0, 45, 45)
        self.deleteButton.setImage(UIImage(named: "MudVideoRecord.bundle/delete"), forState: UIControlState.Normal)
        self.deleteButton.addTarget(self, action: "buttonAction:", forControlEvents: UIControlEvents.TouchUpInside)
        self.deleteButton.center = CGPointMake(37+22.5, self.bounds.size.height-bottomHeight/2)
        self.addSubview(self.deleteButton)
        
        self.progressView = UIProgressView(frame: CGRectMake(0,64+self.bounds.width*0.75,self.bounds.width,1))
        self.progressView.trackTintColor = UIColor(red: 138.0/255.0, green: 137.0/255.0, blue: 137.0/255.0, alpha: 1)
        self.progressView.progressTintColor = UIColor(red: 244.0/255.0, green: 167.0/255.0, blue: 48.0/255.0, alpha: 1)
        self.progressView.transform = CGAffineTransformMakeScale(1.0,3.0)
        self.progressView.progress = 0
        self.addSubview(self.progressView)
        
        let tapGesture = UITapGestureRecognizer()
        tapGesture.addTarget(self, action: "focusAction:")
        self.addGestureRecognizer(tapGesture)
    }
    
    /*extension NSObject {
    
    public func performSelector(aSelector: Selector, withObject anArgument: AnyObject?, afterDelay delay: NSTimeInterval, inModes modes: [String])
    public func performSelector(aSelector: Selector, withObject anArgument: AnyObject?, afterDelay delay: NSTimeInterval)
    public class func cancelPreviousPerformRequestsWithTarget(aTarget: AnyObject, selector aSelector: Selector, object anArgument: AnyObject?)
    public class func cancelPreviousPerformRequestsWithTarget(aTarget: AnyObject)
    
    }*/
    
    private func setupLayoutConstraint() {}
    
    func buttonAction(sender: UIButton?) {
        if self.delegate != nil {
            if sender == self.recordButton {
                self.delegate?.videoControls(self, startOrPauseDidSelected: self.recordButton)
//                NSObject.cancelPreviousPerformRequestsWithTarget(self, selector: "delayAction", object: nil)
//                self.performSelector("delayAction", withObject: nil, afterDelay: 0.20)
            } else if sender == self.finishButton {
                self.delegate?.videoControls(self, finishDidSelected: sender)
            } else if sender == self.deleteButton {
                self.delegate?.videoControls(self, deleteDidSelected: sender)
            } else if sender == self.cameraChangeButton {
                self.delegate?.videoControls(self, cameraChangeDidSelected: sender)
            } else if sender == self.flashModeChangeButton {
                self.delegate?.videoControls(self, flashModeChangeDidSelected: sender)
            } else if sender == self.cancelButton {
                self.delegate?.videoControls(self, cancelDidSelected: sender)
            }
        }
    }
    
    func focusAction(sender: UITapGestureRecognizer) {
        if self.delegate != nil {
            self.delegate?.videoControls(self, focusChangeDidSelected: sender)
        }
    }
    
    func delayAction() {
        self.delegate?.videoControls(self, startOrPauseDidSelected: self.recordButton)
    }
    
    //MARK: -
    func updateProgressView(progress: Float) {
        self.progressView.setProgress(progress, animated: true)
    }
    
    func updateTime(seconds: Float) {
        self.recordTimeLabel.setTitle(String(format: "%0.1f秒",seconds), forState: UIControlState.Normal)
    }
    
    func updateTorchButtonWithTorchMode(mode: AVCaptureTorchMode) {
        switch (mode)
        {
        case AVCaptureTorchMode.Off:
            self.flashModeChangeButton.setImage(UIImage(named: "MudVideoRecord.bundle/flash_close"), forState: UIControlState.Normal)
            break
        case AVCaptureTorchMode.On:
            self.flashModeChangeButton.setImage(UIImage(named: "MudVideoRecord.bundle/flash_open"), forState: UIControlState.Normal)
            break
        case AVCaptureTorchMode.Auto:
            self.flashModeChangeButton.setImage(UIImage(named: "MudVideoRecord.bundle/flash_close"), forState: UIControlState.Normal)
            break
        }
    }
    
    func updateRecordButtonWithStatus(writing: Bool) {
        if writing {
            self.recordButton.setImage(UIImage(named: "MudVideoRecord.bundle/recording.png"), forState: UIControlState.Normal)
        } else {
            self.recordButton.setImage(UIImage(named: "MudVideoRecord.bundle/record_normal.png"), forState: UIControlState.Normal)
        }
        self.flashModeChangeButton.hidden = writing
        self.cameraChangeButton.hidden = writing
        self.cancelButton.hidden = writing
        self.deleteButton.enabled = !writing
    }
}
