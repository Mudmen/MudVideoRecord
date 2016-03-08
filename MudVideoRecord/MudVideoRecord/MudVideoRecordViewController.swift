//
//  MudVideoRecordViewController.swift
//  MudVideoRecord
//
//  Created by TimTiger on 16/1/19.
//  Copyright © 2016年 Mudmen. All rights reserved.
//

import UIKit
import AVFoundation
import AssetsLibrary
import CoreFoundation

public let MudVideoRecordDidFinished = "MudVideoRecordDidFinished"

public enum MudVideoRecordSetupResult: Int {
    case Success
    case NotAuthorized
    case ConfigurationFailed
}

public class MudVideoRecordViewController: UIViewController,UIAlertViewDelegate {
    
    //Public
    lazy public var videoID: String = { return "1" }()
    weak var delegate: MudVideoRecordViewControllerDelegate?
    
    public private(set) var running: Bool = { return false }()
    private var writing: Bool = { return false }()
    
    /// Views
    private var previewView: MudVideoPreviewView!
    private var controls: MudVideoControls!
    
    /// Camera config
    private var sessionQueue: dispatch_queue_t!
    private var session: AVCaptureSession!
    private var videoInput: AVCaptureDeviceInput!
    private var videoOutput: AVCaptureVideoDataOutput!
    private var movieOutput: AVCaptureMovieFileOutput!
    private var audioInput: AVCaptureDeviceInput!
    private var audioOutput: AVCaptureAudioDataOutput!
    private var setupResult: MudVideoRecordSetupResult!
    
    /// File Writer
    private var assetWriter: AVAssetWriter!
    private var videoAssetWriterInput: AVAssetWriterInput!
    private var audioAssetWriterInput: AVAssetWriterInput!
    lazy private var isCroping: Bool = { return false}()
    lazy private var frameOneSecond: Int! = { return 14 }() //1秒多少帧
    private var frameDuration: CMTime! //一帧的时长
    private var nextFpts: CMTime! //下一帧
    lazy private var maxFrame: Int = { return 300*self.frameOneSecond }() //最大帧数 每秒24帧 10秒
    lazy private var minFrame: Int = { return self.frameOneSecond*3 }() //最小帧数 3秒
    lazy private var currentFrame: Int = { return 0 }()  //当前帧数
    
    private var videoFileCacheURL: NSURL!
    private var tmpVideoCacheURL: NSURL!
    lazy private var videoWidth: CGFloat = { return 640 }()
    lazy private var videoHeight: CGFloat = { return 480 }()
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        ///初始化需要用到的文件路径和 一些设置
        self.initData()
        
        //初始化视图
        self.initView()
        
        ///初始化拍摄类
        self.initSession()
        
        //判断是否有使用摄像头的权限
        self.checkMidiaTypeVideoAuthorizationStatus()
        
        dispatch_async(self.sessionQueue) { () -> Void in
            if ( self.setupResult != MudVideoRecordSetupResult.Success ) {
                return
            }
            ///设置输入输出
            self.initInputOutput()
        }
        
        //添加观察
        self.addObserverForNotification()
    }
    
    public override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        
        //判断拍摄权限
        self.checkMidiaTypeVideoAuthorizationStatus()
    
        dispatch_async(self.sessionQueue) { () -> Void in
            if self.setupResult == MudVideoRecordSetupResult.Success {
                //如果有权限，运行摄像头
                self.startCameraRunning()
            } else {
                //没有权限，提示
                self.showAuthorizationStatusRemind()
            }
        }
    }
    
    public override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
        
        dispatch_async(self.sessionQueue) { () -> Void in
            if self.setupResult == MudVideoRecordSetupResult.Success {
                //视图消失，摄像头不停止运行，但是文件写入应该停止
                self.stopVideoWrite()
            }
        }
    }
    
    //MARK - Notification
    private func addObserverForNotification() {
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "notificationAction:", name: UIApplicationDidBecomeActiveNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "notificationAction:", name: UIApplicationDidEnterBackgroundNotification, object: nil)
    }
    
    func notificationAction(sender: NSNotification?) {
        
        //无论是程序进入后台还是回到前台，都检查是否有拍摄权限
        self.checkMidiaTypeVideoAuthorizationStatus()
        
        dispatch_async(self.sessionQueue) { () -> Void in
            if sender?.name == UIApplicationDidBecomeActiveNotification {  //当程序进入前台
                if self.setupResult == MudVideoRecordSetupResult.Success {    //如果有拍摄权限，应该运行摄像头
                    self.startCameraRunning()
                } else {    //没有权限则给予提示
                    self.showAuthorizationStatusRemind()
                }
            } else if sender?.name == UIApplicationDidEnterBackgroundNotification {  //当程序进入后台
                if self.setupResult == MudVideoRecordSetupResult.Success { //摄像头应该停止运行，文件也停止写入,就是停止录制
                    self.stopRecord()
                }
            }
        }
    }
    
    //MARK: - Private API
    private func initData() {
        self.videoFileCacheURL = MudVideoCacheManager.getfileURLWithVideoID(self.videoID)
        self.tmpVideoCacheURL = MudVideoCacheManager.getfileURLWithVideoID("tmp")
        
        ///清空文件路径
        MudVideoCacheManager.deleteFile(self.tmpVideoCacheURL)
        MudVideoCacheManager.deleteFile(self.videoFileCacheURL)
        
        self.setupResult = MudVideoRecordSetupResult.Success
        self.sessionQueue = dispatch_queue_create("session queue", DISPATCH_QUEUE_SERIAL );
    }
    
    private func initView() {
        
        self.view.backgroundColor = UIColor.whiteColor()
        self.videoWidth = self.view.bounds.size.width
        self.videoHeight = self.view.bounds.size.width*0.75
        
        self.previewView  = MudVideoPreviewView(frame: CGRectMake(0,64,self.videoWidth,self.videoHeight))
        self.previewView.backgroundColor = UIColor.blackColor()
        self.previewView.clipsToBounds = true
        self.view.addSubview(self.previewView)
        
        self.controls = MudVideoControls(frame: self.view.bounds)
        self.controls.delegate = self
        self.controls.userInteractionEnabled = true
        self.view.addSubview(self.controls)
        
    }
    
    private func initSession() {
        self.frameDuration = CMTimeMakeWithSeconds(1.0/Double(self.frameOneSecond), Int32(self.frameOneSecond))
        self.session = AVCaptureSession()
        self.session.sessionPreset = AVCaptureSessionPreset640x480
        self.previewView.session = self.session
    }
    
    private func initInputOutput() {
        do {
            self.session.beginConfiguration()
            let videoDevice = self.deviceWithMediaType(AVMediaTypeVideo, preferringPosition: AVCaptureDevicePosition.Back)
            self.videoInput = try AVCaptureDeviceInput(device: videoDevice)
            self.videoOutput = AVCaptureVideoDataOutput()
            self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey: NSNumber(unsignedInt: kCVPixelFormatType_32BGRA)]
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
                self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
            } else {
                self.setupResult = MudVideoRecordSetupResult.ConfigurationFailed
            }
            
            if self.session.canAddInput(self.videoInput) {
                self.session.addInput(self.videoInput)
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
                    previewLayer.connection.videoOrientation = AVCaptureVideoOrientation.Portrait
                    previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill
                })
            } else {
                self.setupResult = MudVideoRecordSetupResult.ConfigurationFailed
            }
            let audioDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeAudio)
            self.audioInput = try AVCaptureDeviceInput(device: audioDevice)
            if self.session.canAddInput(self.audioInput) {
                self.session.addInput(self.audioInput)
            }
            self.audioOutput = AVCaptureAudioDataOutput()
            if self.session.canAddOutput(self.audioOutput) {
                self.session.addOutput(self.audioOutput)
                self.audioOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
            }
            self.session.commitConfiguration()
        } catch _ as NSError {
            self.setupResult = MudVideoRecordSetupResult.ConfigurationFailed
        }
    }
    
    private func initAssetWriterWithFormatDescription(format: CMFormatDescription?)->Bool {
        
        if format == nil {
            return false
        }
        
        do {
            try self.assetWriter = AVAssetWriter(URL: self.tmpVideoCacheURL , fileType: AVFileTypeMPEG4)
            let videoCompressionProperties = [AVVideoAverageBitRateKey: NSNumber(double: 4000000),AVVideoMaxKeyFrameIntervalKey: 20,AVVideoProfileLevelKey: AVVideoProfileLevelH264Main30]
            let videoOutputSettings = [AVVideoCodecKey: AVVideoCodecH264,AVVideoWidthKey: NSNumber(float: Float(self.videoWidth)),AVVideoHeightKey: NSNumber(float: Float(self.videoHeight)),AVVideoCompressionPropertiesKey: videoCompressionProperties]
            self.videoAssetWriterInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: videoOutputSettings)
            self.videoAssetWriterInput.expectsMediaDataInRealTime = true
            if self.assetWriter.canAddInput(self.videoAssetWriterInput) {
                self.assetWriter.addInput(self.videoAssetWriterInput)
            }
            
            var acl = AudioChannelLayout()
            acl.mChannelLayoutTag = kAudioChannelLayoutTag_Mono
            let audioOutputSettings = [AVFormatIDKey: NSNumber(unsignedInt: kAudioFormatMPEG4AAC),AVSampleRateKey: NSNumber(int: 16000),AVNumberOfChannelsKey: NSNumber(int: 1),AVChannelLayoutKey: NSData(bytes: &acl, length: sizeof (AudioChannelLayout))]
            self.audioAssetWriterInput = AVAssetWriterInput(mediaType: AVMediaTypeAudio, outputSettings: audioOutputSettings)
            if self.assetWriter.canAddInput(self.audioAssetWriterInput) {
                self.assetWriter.addInput(self.audioAssetWriterInput)
            }
            
            var rotationDegrees: CGFloat = 90
            if self.videoInput.device.position == AVCaptureDevicePosition.Front {
                rotationDegrees = -90
            }
            let rotationRadians = rotationDegrees*CGFloat(M_PI)/180
            self.videoAssetWriterInput.transform = CGAffineTransformMakeRotation(rotationRadians)
            
            self.nextFpts = kCMTimeZero
            self.assetWriter.startWriting()
            self.assetWriter.startSessionAtSourceTime(self.nextFpts)
            return true
        } catch _ as NSError {
            return false
        }
    }
    
    private func setupVideoZoomFactor() {
        let videoDevice = self.videoInput.device
        do {
            try videoDevice.lockForConfiguration()
            videoDevice.videoZoomFactor = 1.45
            videoDevice.unlockForConfiguration()
        } catch _ {
            
        }
    }
    
    private func setupFrameDuration() {
        let videoDevice = self.videoInput.device
        do {
            try videoDevice.lockForConfiguration()
            videoDevice.activeVideoMinFrameDuration = CMTimeMake(1,Int32(self.frameOneSecond))
            videoDevice.activeVideoMaxFrameDuration = CMTimeMake(1,Int32(self.frameOneSecond))
            videoDevice.unlockForConfiguration()
        } catch _ {
            
        }
    }
    
    private func deviceWithMediaType(type: String,preferringPosition: AVCaptureDevicePosition)->AVCaptureDevice {
        var defaultDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo)
        let devices = AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo) as! [AVCaptureDevice]
        for device in devices {
            if device.position == preferringPosition {
                defaultDevice = device
                break;
            }
        }
        return defaultDevice
    }
    
    private func setTorchMode(tourMode: AVCaptureTorchMode,forDevice device: AVCaptureDevice) {
        if device.hasTorch && device.isTorchModeSupported(tourMode) {
            do {
                try device.lockForConfiguration()
                device.torchMode = tourMode
                device.unlockForConfiguration()
            } catch _ {
                
            }
        }
    }

    private func focusWithMode(focusMode: AVCaptureFocusMode, exposeWithMode exposureMode: AVCaptureExposureMode,atDevicePoint point: CGPoint, monitorSubjectAreaChange: Bool) {
        dispatch_async(self.sessionQueue) { () -> Void in
            let videoDevice = self.videoInput.device
            do {
                try videoDevice.lockForConfiguration()
                if videoDevice.focusPointOfInterestSupported && videoDevice.isFocusModeSupported(focusMode) {
                    videoDevice.focusPointOfInterest = point
                    videoDevice.focusMode = focusMode
                }
                
                if videoDevice.exposurePointOfInterestSupported && videoDevice.isExposureModeSupported(exposureMode) {
                    videoDevice.exposurePointOfInterest = point
                    videoDevice.exposureMode = exposureMode
                }
                
                videoDevice.subjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                videoDevice.unlockForConfiguration()
            } catch _ {
                
            }
        }
    }
    
    private func checkMidiaTypeVideoAuthorizationStatus() {
        let authorizationStatus = AVCaptureDevice.authorizationStatusForMediaType(AVMediaTypeVideo)
        if authorizationStatus == AVAuthorizationStatus.NotDetermined {
            //用户还没选择，就申请获取权限
            dispatch_suspend(self.sessionQueue)
            AVCaptureDevice.requestAccessForMediaType(AVMediaTypeVideo, completionHandler: { (granted) -> Void in
                if granted == false {
                    self.setupResult = MudVideoRecordSetupResult.NotAuthorized
                }
                dispatch_resume(self.sessionQueue)
            })
        } else if authorizationStatus == AVAuthorizationStatus.Authorized {
            self.setupResult = MudVideoRecordSetupResult.Success
        } else {
            self.setupResult = MudVideoRecordSetupResult.ConfigurationFailed
        }
    }
    
    private func showAuthorizationStatusRemind() {
        dispatch_async(dispatch_get_main_queue()) { () -> Void in
            let alertView = UIAlertView(title: "无法启动相机", message: "请为趣皮士开放相机权限：手机设置->隐私->相机->趣皮士（打开）", delegate: self, cancelButtonTitle: "确定")
            alertView.show()
        }
    }
    
    public func alertView(alertView: UIAlertView, clickedButtonAtIndex buttonIndex: Int) {
        dispatch_async(dispatch_get_main_queue(), { () -> Void in
            self.dismissViewControllerAnimated(true, completion: { () -> Void in
            })
        })
    }

    private func showError(errorString: String) {
        dispatch_async(dispatch_get_main_queue(), { () -> Void in
            NSLog(errorString)
//         SVProgressHUD.showImage(nil, status: errorString)
        })
    }
    
    //MARK -
    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
        MudVideoCacheManager.deleteFile(self.tmpVideoCacheURL)
    }
}

extension MudVideoRecordViewController: MudVideoControlsDelegate {
    func videoControls(controls: MudVideoControls,startOrPauseDidSelected sendr: AnyObject?) {
        if self.running == false {
            self.startCameraRunning()
        }
        if self.writing {
            self.stopVideoWrite()
        } else {
            self.startVideoWrite()
        }
    }
    
    func videoControls(controls: MudVideoControls,finishDidSelected sendr: AnyObject?) {
        if self.currentFrame < self.minFrame {
            //拍摄时间不够 不能停止
            self.showError("time not enough")
//        SVProgressHUD.showImage(nil, status: MudLocalString.stringForKey("MomentVideoTimeNotEnough"))
            return
        }
        dispatch_async(self.sessionQueue) { () -> Void in
            
            self.finishRecordWithCompletionHandler({ (error) -> Void in
                if error != nil {
                    self.showError("视频结束录制失败")
                    return
                }
                self.cropVideoSquareWithVideoURL(self.tmpVideoCacheURL, targetURL: self.videoFileCacheURL, completionHandler: { (error, thumbImage) -> Void in
                    if error == nil && self.delegate != nil {
                        dispatch_async(dispatch_get_main_queue(), { () -> Void in
                            self.delegate?.mudVideoRecordViewController(self, didFinishedRecord: self.videoFileCacheURL, firstImage: thumbImage!)
                        })
                    } else if error != nil  {
                        self.showError("视频保存失败")
                    } else {
                        self.showError("视频保存成功")
                    }
                })
            })
        }
    }
    
    func videoControls(controls: MudVideoControls,cancelDidSelected sendr: AnyObject?) {
        
        if self.writing == true {
            return
        }
        
        dispatch_async(self.sessionQueue) { () -> Void in
            self.finishRecordWithCompletionHandler({ (error) -> Void in
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    self.dismissViewControllerAnimated(true, completion: { () -> Void in
                    })
                })
            })
        }
    }
    
    func videoControls(controls: MudVideoControls,deleteDidSelected sendr: AnyObject?) {
        if self.writing == false {
            self.controls.updateProgressView(0)
            self.controls.updateTime(0)
            self.assetWriter = nil
            MudVideoCacheManager.deleteFile(self.tmpVideoCacheURL)
            self.currentFrame = 0
        }
    }
    
    func videoControls(controls: MudVideoControls,cameraChangeDidSelected sendr: AnyObject?) {
        
        if self.writing {
            return
        }
        
        controls.cameraChangeButton.enabled = false
        controls.flashModeChangeButton.enabled = false
        dispatch_async(self.sessionQueue) { () -> Void in
            let currentVideoDevice = self.videoInput.device
            var preferredPosition = AVCaptureDevicePosition.Unspecified
            let currentPosition = currentVideoDevice.position
            var enableFlash: Bool = false
            switch (currentPosition) {
                case AVCaptureDevicePosition.Unspecified:
                    break
                case AVCaptureDevicePosition.Front:
                    preferredPosition = AVCaptureDevicePosition.Back
                    enableFlash = true
                    break
                case AVCaptureDevicePosition.Back:
                    preferredPosition = AVCaptureDevicePosition.Front
                    break
            }
            do {
                let videoDevice = self.deviceWithMediaType(AVMediaTypeVideo, preferringPosition: preferredPosition)
                let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                self.session.beginConfiguration()
                self.session.removeInput(self.videoInput)
                if self.session.canAddInput(videoDeviceInput) {
                    self.session.addInput(videoDeviceInput)
                    self.setTorchMode(AVCaptureTorchMode.Off, forDevice: videoDevice)
                    self.videoInput =  videoDeviceInput
                } else {
                    self.session.addInput(self.videoInput)
                }
                self.session.commitConfiguration()
                self.setupFrameDuration()
            } catch _ as NSError {
                
            }
            
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    controls.updateTorchButtonWithTorchMode(AVCaptureTorchMode.Off)
                    controls.flashModeChangeButton.enabled = enableFlash
                    controls.cameraChangeButton.enabled = true
            })
            
        }
    }
    
    func videoControls(controls: MudVideoControls,flashModeChangeDidSelected sendr: AnyObject?) {
        
        if self.writing {
            return
        }
        
        controls.cameraChangeButton.enabled = false
        controls.flashModeChangeButton.enabled = false
        dispatch_async(self.sessionQueue) { () -> Void in
            let  videoDevice = self.videoInput.device
            var torchMode = videoDevice.torchMode
            switch (torchMode)
            {
            case AVCaptureTorchMode.Off:
                torchMode = AVCaptureTorchMode.On
                break
            case AVCaptureTorchMode.On:
                torchMode = AVCaptureTorchMode.Off
                break
            default:
                torchMode = AVCaptureTorchMode.Off
                break
            }
            self.session.beginConfiguration()
            self.setTorchMode(torchMode, forDevice: videoDevice)
            self.session.commitConfiguration()
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                controls.flashModeChangeButton.enabled = true
                controls.cameraChangeButton.enabled = true
                controls.updateTorchButtonWithTorchMode(torchMode)
            })
        }
    }
    
    func videoControls(controls: MudVideoControls, focusChangeDidSelected sender: UITapGestureRecognizer) {
        let devicePoint = (self.previewView.layer as! AVCaptureVideoPreviewLayer).captureDevicePointOfInterestForPoint(sender.locationInView(sender.view))
        self.focusWithMode(AVCaptureFocusMode.ContinuousAutoFocus, exposeWithMode: AVCaptureExposureMode.ContinuousAutoExposure, atDevicePoint: devicePoint, monitorSubjectAreaChange: true)
    }
    
    //开始录制视频
    func startRecord() {
        self.startCameraRunning()
        self.startVideoWrite()
    }
    
    //停止录制视频
    func stopRecord() {
        self.stopCameraRuning()
        self.stopVideoWrite()
    }
    
    //开启摄像头运行
    func startCameraRunning() {
        self.session.startRunning()
        self.running = self.session.running
        self.setupVideoZoomFactor()
        self.setupFrameDuration()
    }
    
    //关闭摄像头运行
    func stopCameraRuning() {
        
        //关闭闪光灯
        dispatch_async(dispatch_get_main_queue()) { () -> Void in
            self.controls.updateTorchButtonWithTorchMode(AVCaptureTorchMode.Off)
        }
        self.session.beginConfiguration()
        self.setTorchMode(AVCaptureTorchMode.Off, forDevice: self.videoInput.device)
        self.session.commitConfiguration()
        
        //摄像头停止运行
        self.session.stopRunning()
        self.running = self.session.running
    }
    
    //允许视频写入
    func startVideoWrite() {
        self.writing = true
        dispatch_async(dispatch_get_main_queue()) { () -> Void in
            self.controls.updateRecordButtonWithStatus(self.writing)
        }
    }
    
    //停止视频写入
    func stopVideoWrite() {
        self.writing = false
        dispatch_async(dispatch_get_main_queue()) { () -> Void in
            self.controls.updateRecordButtonWithStatus(self.writing)
        }
    }
    
    func startVideoCrop() {
        self.isCroping = true
        self.showError("Croping")
        dispatch_async(dispatch_get_main_queue()) { () -> Void in
            self.controls.finishButton.enabled = false
        }
    }
    
    func endVideoCrop() {
        self.isCroping = false
        dispatch_async(dispatch_get_main_queue()) { () -> Void in
            self.controls.finishButton.enabled = true
        }
    }
}

extension MudVideoRecordViewController: AVCaptureAudioDataOutputSampleBufferDelegate,AVCaptureVideoDataOutputSampleBufferDelegate {
    
    public func captureOutput(captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
        dispatch_async(self.sessionQueue) { () -> Void in
            if self.writing {
                if self.assetWriter == nil {
                    if self.initAssetWriterWithFormatDescription(CMSampleBufferGetFormatDescription(sampleBuffer)!) == false {
                        self.showError("视频存储初始化失败")
                        return
                    }
                }
                var timingInfo = kCMTimingInfoInvalid
                timingInfo.duration = self.frameDuration
                timingInfo.presentationTimeStamp = self.nextFpts
                var sbufWithNewTiming: CMSampleBuffer? = nil
                let error = CMSampleBufferCreateCopyWithNewTiming(kCFAllocatorDefault, sampleBuffer, 1, &timingInfo, &sbufWithNewTiming)
                if error != 0 {
                    return
                }
                
                if captureOutput == self.videoOutput {
                    if self.videoAssetWriterInput.readyForMoreMediaData && sbufWithNewTiming != nil {
                        if self.videoAssetWriterInput.appendSampleBuffer(sbufWithNewTiming!) {
                            self.nextFpts = CMTimeAdd(self.frameDuration, self.nextFpts)
                        } else {
                            //hand error
                        self.showError("视频存入数据失败")
                        }
                    } else {
                        //hand error
                        self.showError("视频无法存入")
                    }
                    
                    //update progress
                    self.currentFrame++
                    let progress = Float(self.currentFrame)/Float(self.maxFrame)
                    dispatch_async(dispatch_get_main_queue(), { () -> Void in
                        self.controls.updateProgressView(progress)
                        self.controls.updateTime(Float(self.currentFrame)/Float(self.frameOneSecond))
                    })

                    //if max stop
                    if self.currentFrame >= self.maxFrame {
                        
                        self.finishRecordWithCompletionHandler({ (error) -> Void in
                            if error != nil {
                                self.showError("视频结束录制失败")
                                return
                            }
        
                            self.cropVideoSquareWithVideoURL(self.tmpVideoCacheURL, targetURL: self.videoFileCacheURL, completionHandler: { (error, thumbImage) -> Void in
                                if error == nil && self.delegate != nil {
                                    dispatch_async(dispatch_get_main_queue(), { () -> Void in
                                        self.delegate?.mudVideoRecordViewController(self, didFinishedRecord: self.videoFileCacheURL, firstImage: thumbImage!)
                                    })
                                } else {
                                    self.showError("视频保存失败")
                                }
                            })
                        })
                    }
                } else if captureOutput == self.audioOutput {
                    if (self.assetWriter.status.rawValue > AVAssetWriterStatus.Writing.rawValue) {
                        if (self.assetWriter.status == AVAssetWriterStatus.Failed) {
                            return
                        }
                    }
                    if self.audioAssetWriterInput.readyForMoreMediaData && sbufWithNewTiming != nil {
                        if self.audioAssetWriterInput.appendSampleBuffer(sbufWithNewTiming!) == false {
                            self.showError("音频存入失败")
                        }
                    }
                }
            }
        }
    }
    //success: () -> Void, failed: (NSError) -> Void)
    private func finishRecordWithCompletionHandler(handler: (error: NSError?) -> Void) {
        if self.running == false {
            handler(error: nil)
            return
        }
        
        self.stopRecord()
        
        if self.assetWriter != nil {
            if self.assetWriter.status == AVAssetWriterStatus.Writing {
                //如果是正在写入，立刻停止写入，做好文件收尾
                self.videoAssetWriterInput.markAsFinished()
                self.assetWriter.finishWritingWithCompletionHandler({ () -> Void in
                    if self.assetWriter.status == AVAssetWriterStatus.Completed {
                        self.videoAssetWriterInput = nil;
                        self.assetWriter = nil;
                        handler(error: nil)
                    } else {
                        handler(error: self.assetWriter.error)
                    }
                })
            } else {
                handler(error: nil)
            }
        } else {
            handler(error: nil)
        }
    }
}

extension MudVideoRecordViewController {
    private func cropVideoSquareWithVideoURL(videoURL: NSURL,targetURL: NSURL,completionHandler: (error: NSError?,thumbImage: UIImage?) -> Void) {
        
        if self.isCroping == true {
            return
        }
        
        self.startVideoCrop()
        
        //load our movie Asset
        let asset = AVAsset(URL: videoURL)
        
        //create an avassetrack with our asset
        let clipVideoTracks = asset.tracksWithMediaType(AVMediaTypeVideo)
        if clipVideoTracks.count < 1 {
            completionHandler(error: NSError(domain: "文件不存在", code: 400, userInfo: nil), thumbImage: nil)
            self.endVideoCrop()
            return
        }
        let clipVideoTrack = clipVideoTracks[0]
        
        //create a video composition and preset some settings
        let videoComposition = AVMutableVideoComposition()
        
        var renderWidth = Int(clipVideoTrack.naturalSize.height) //如果不为整数，永远不可能被整除的
        while(renderWidth%16 != 0) {
            renderWidth--
        }
        
        var renderHeight = Int(clipVideoTrack.naturalSize.height*0.75) //如果不为整数，永远不可能被整除的
        while(renderHeight%16 != 0) {
            renderHeight--
        }
        
        videoComposition.frameDuration = CMTimeMake(1, Int32(self.frameOneSecond))
        videoComposition.renderSize = CGSizeMake(CGFloat(renderWidth), CGFloat(renderHeight))
        
        //create a video instruction
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRangeMake(kCMTimeZero, CMTimeMakeWithSeconds(60, Int32(self.frameOneSecond)));
        
        let transformer = AVMutableVideoCompositionLayerInstruction(assetTrack: clipVideoTrack)
        
        //按屏幕比例，算出顶部需要裁剪多少
        var translationY: CGFloat = -64
        if  self.view.bounds.size.height > 568 {
            translationY =  -64*(self.view.bounds.size.height/568)
        }
        var translationX = Int(clipVideoTrack.naturalSize.height) //如果不为整数，永远不可能被整除的
        while(translationX%16 != 0) {
            translationX--
        }
        let t1 = CGAffineTransformMakeTranslation(CGFloat(translationX), translationY)
        
        //Make sure the square is portrait
        let t2 = CGAffineTransformRotate(t1, CGFloat(M_PI_2))
        
        let finalTransform = t2
        transformer.setTransform(finalTransform, atTime: kCMTimeZero)
        
        //add the transformer layer instructions, then add to video composition
        instruction.layerInstructions = [transformer]
        videoComposition.instructions = [instruction]
        
        //Remove any prevouis videos at that path
        MudVideoCacheManager.deleteFile(targetURL)
        
        //Export
        let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality)
        exporter?.shouldOptimizeForNetworkUse = false
        exporter?.videoComposition = videoComposition
        exporter?.outputURL = targetURL
        exporter?.outputFileType = AVFileTypeMPEG4
        
        dispatch_async(dispatch_get_main_queue()) { () -> Void in
            exporter?.exportAsynchronouslyWithCompletionHandler({ () -> Void in
                if exporter?.status == AVAssetExportSessionStatus.Completed {
                    self.captureThumbImageWithTargetURL(targetURL, completionHandler: { (error, image) -> Void in
                        completionHandler(error: error, thumbImage: image)
                        self.endVideoCrop()
                    })
                } else {
                    completionHandler(error: NSError(domain: "error", code: 400, userInfo: nil), thumbImage: nil)
                    self.endVideoCrop()
                }
            })
        }
    }
    
    private func captureThumbImageWithTargetURL(targetURL: NSURL, completionHandler: (error: NSError?,image: UIImage?)->Void) {
        let asset = AVAsset(URL: targetURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let thumbTime = CMTimeMakeWithSeconds(0,30)
        generator.generateCGImagesAsynchronouslyForTimes([NSValue(CMTime: thumbTime)]) { (requestedTime, im, actualTime, result, error) -> Void in
            if result == AVAssetImageGeneratorResult.Succeeded && im != nil {
                let thumbImg = UIImage(CGImage: im!)
                completionHandler(error: nil, image: thumbImg)
            } else {
                completionHandler(error: NSError(domain: "error", code: 400, userInfo: nil), image: nil)
            }
        }
    }
}

public class MudVideoCacheManager: NSObject {
    public class func deleteFile(fileURL: NSURL)->Bool {
        do {
            try NSFileManager.defaultManager().removeItemAtURL(fileURL)
            return true
        } catch _ as NSError {
            return false
        }
    }
    
    public class func deleteFileWithPath(filePath: String?)->Bool {
        
        if filePath == nil {
            return true
        }
        
        let fileURL = NSURL(fileURLWithPath: filePath!)
        do {
            try NSFileManager.defaultManager().removeItemAtURL(fileURL)
            return true
        } catch _ as NSError {
            return false
        }
    }
    
    private class func getfileURLWithVideoID(videoID: String)->NSURL? {
        let path = NSHomeDirectory().stringByAppendingString("/Library/Video_Cache")
        if NSFileManager.defaultManager().fileExistsAtPath(path) == false {
            do {
                try NSFileManager.defaultManager().createDirectoryAtPath(path, withIntermediateDirectories: true, attributes: nil)
            } catch _ {
                
            }
        }
        return NSURL(fileURLWithPath: path.stringByAppendingFormat("/%@.mp4", videoID))
    }
}

public protocol MudVideoRecordViewControllerDelegate: NSObjectProtocol {
    func mudVideoRecordViewController(controller: MudVideoRecordViewController,didFinishedRecord url: NSURL,firstImage: UIImage)
}
