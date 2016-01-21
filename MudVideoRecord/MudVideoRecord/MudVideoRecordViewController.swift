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

enum MudVideoRecordSetupResult: Int {
    case Success
    case NotAuthorized
    case ConfigurationFailed
}

public class MudVideoRecordViewController: UIViewController {

    //Public
    lazy public var videoFileCacheURL: NSURL = {
        let paths = NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory.DocumentDirectory, NSSearchPathDomainMask.UserDomainMask, true)
        if paths.count > 0 {
            return NSURL(fileURLWithPath: paths.first!.stringByAppendingString("/video.mp4"))
        }
        return NSURL(fileURLWithPath: NSTemporaryDirectory().stringByAppendingString("/video.mp4"))
    }()
    public private(set) var running: Bool = { return false }()
    private var writing: Bool = { return false }()
    
    /// Views
    private var previewView: MudVideoPreviewView!
    private var controls: MudVideoControls!
    
    /// Camera config
    private var sessionQueue: dispatch_queue_t!
    private var session: AVCaptureSession!
    private var videoDevice: AVCaptureDevice!
    private var videoInput: AVCaptureDeviceInput!
    private var videoOutput: AVCaptureVideoDataOutput!
    private var movieOutput: AVCaptureMovieFileOutput!
    private var audioDevice: AVCaptureDevice!
    private var audioInput: AVCaptureDeviceInput!
    private var audioOutput: AVCaptureAudioDataOutput!
    private var setupResult: MudVideoRecordSetupResult!
    
    /// File Writer
    private var assetWriter: AVAssetWriter!
    private var videoAssetWriterInput: AVAssetWriterInput!
    private var audioAssetWriterInput: AVAssetWriterInput!
    private var frameDuration: CMTime! //一帧的时长
    private var nextFpts: CMTime! //下一帧
    lazy private var maxFrame: Int = 50*24 //最大帧数 每秒24帧 50秒
    lazy private var minFrame: Int = 24*10 //最小帧数 10秒
    lazy private var currentFrame: Int = 0  //当前帧数
    
    lazy private var videoWidth: CGFloat = { return 640 }()
    lazy private var videoHeight: CGFloat = { return 480 }()
    lazy private var tmpVideoCacheURL = { return NSURL(fileURLWithPath: NSTemporaryDirectory().stringByAppendingString("/tmp.mp4")) }()
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        self.initView()
        self.initSession()
        self.setupResult = MudVideoRecordSetupResult.Success
        self.sessionQueue = dispatch_queue_create("session queue", DISPATCH_QUEUE_SERIAL );
        //判断是否有使用摄像头的权限
        switch(AVCaptureDevice.authorizationStatusForMediaType(AVMediaTypeVideo)) {
        case AVAuthorizationStatus.NotDetermined:
            //用户还没选择，就申请获取权限
            dispatch_suspend(self.sessionQueue)
            AVCaptureDevice.requestAccessForMediaType(AVMediaTypeVideo, completionHandler: { (granted) -> Void in
                if granted == false {
                    self.setupResult = MudVideoRecordSetupResult.NotAuthorized
                }
                dispatch_resume(self.sessionQueue)
            })
        case AVAuthorizationStatus.Authorized:
            self.setupResult = MudVideoRecordSetupResult.Success
        default:
            self.setupResult = MudVideoRecordSetupResult.NotAuthorized
        }
        dispatch_async(self.sessionQueue) { () -> Void in
            if ( self.setupResult != MudVideoRecordSetupResult.Success ) {
                return
            }
            self.initInputOutput()
        }
    }
    
    public override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        dispatch_async(self.sessionQueue) { () -> Void in
            if self.setupResult == MudVideoRecordSetupResult.Success {
                self.session.startRunning()
                self.running = self.session.running
            } else {
                //remind
            }
        }
    }
    
    public override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
        dispatch_async(self.sessionQueue) { () -> Void in
            if self.setupResult == MudVideoRecordSetupResult.Success {
                self.session.stopRunning()
                self.running = self.session.running
            } else {
                //remind
            }
        }
    }
    
    //MARK: - Private API
    private func initView() {
        
        self.view.backgroundColor = UIColor.whiteColor()
        self.videoWidth = self.view.bounds.size.width
        self.videoHeight = self.view.bounds.size.width*0.75
        
        self.previewView  = MudVideoPreviewView(frame: CGRectMake(0,64,self.videoWidth,self.videoHeight))
        self.previewView.backgroundColor = UIColor.grayColor()
        self.view.addSubview(self.previewView)
        
        self.controls = MudVideoControls(frame: self.view.bounds)
        self.controls.delegate = self
        self.view.addSubview(self.controls)
    }
    
    private func initSession() {
        self.frameDuration = CMTimeMakeWithSeconds(1.0/24, 24)
        self.session = AVCaptureSession()
        self.session.sessionPreset = AVCaptureSessionPresetMedium
        self.previewView.session = self.session
    }
    
    private func initInputOutput() {
        do {
            self.videoDevice = self.deviceWithMediaType(AVMediaTypeVideo, preferringPosition: AVCaptureDevicePosition.Back)
            self.videoInput = try AVCaptureDeviceInput(device: self.videoDevice)
            self.videoOutput = AVCaptureVideoDataOutput()
            self.session.beginConfiguration()
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
            self.audioDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeAudio)
            self.audioInput = try AVCaptureDeviceInput(device: self.audioDevice)
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
            self.setupResult = MudVideoRecordSetupResult.ConfigurationFailed
            return false
        }
        
        do {
            self.deleteFile(self.tmpVideoCacheURL)
            try self.assetWriter = AVAssetWriter(URL: self.tmpVideoCacheURL , fileType: AVFileTypeMPEG4)
            let videoCompressionProperties = [AVVideoAverageBitRateKey: NSNumber(double: 480*1024)]
            NSLog("%f   %f", self.videoWidth,self.videoHeight)
            let videoOutputSettings = [AVVideoCodecKey: AVVideoCodecH264,AVVideoWidthKey: NSNumber(float: Float(self.videoWidth)),AVVideoHeightKey: NSNumber(float: Float(self.videoHeight)),AVVideoCompressionPropertiesKey: videoCompressionProperties]
            self.videoAssetWriterInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: videoOutputSettings)
            self.videoAssetWriterInput.expectsMediaDataInRealTime = true
            if self.assetWriter.canAddInput(self.videoAssetWriterInput) {
                self.assetWriter.addInput(self.videoAssetWriterInput)
            }
            
            var acl = AudioChannelLayout()
            acl.mChannelLayoutTag = kAudioChannelLayoutTag_Mono
            let audioOutputSettings = [AVFormatIDKey: NSNumber(unsignedInt: kAudioFormatMPEG4AAC),AVSampleRateKey: NSNumber(int: 32000),AVNumberOfChannelsKey: NSNumber(int: 1),AVChannelLayoutKey: NSData(bytes: &acl, length: sizeof (AudioChannelLayout))]
            self.audioAssetWriterInput = AVAssetWriterInput(mediaType: AVMediaTypeAudio, outputSettings: audioOutputSettings)
            if self.assetWriter.canAddInput(self.audioAssetWriterInput) {
                self.assetWriter.addInput(self.audioAssetWriterInput)
            }
            
            let rotationDegrees: CGFloat = 90
            let rotationRadians = rotationDegrees*CGFloat(M_PI)/180
            self.videoAssetWriterInput.transform = CGAffineTransformMakeRotation(rotationRadians)
            
            self.nextFpts = kCMTimeZero
            self.assetWriter.startWriting()
            self.assetWriter.startSessionAtSourceTime(self.nextFpts)
            return true
        } catch _ as NSError {
            self.setupResult = MudVideoRecordSetupResult.ConfigurationFailed
            return false
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
}

extension MudVideoRecordViewController: MudVideoControlsDelegate {
    func videoControls(controls: MudVideoControls,startOrPauseDidSelected sendr: AnyObject?) {
        if self.writing {
            self.writing = false
        } else {
            self.writing = true
        }
        self.controls.updateRecordButtonWithStatus(self.writing)
    }
    
    func videoControls(controls: MudVideoControls,finishDidSelected sendr: AnyObject?) {
        if self.currentFrame < self.minFrame {
            //拍摄时间不够 不能停止
//         self.controls.showTimeNotEnough()
            return
        }
        dispatch_async(self.sessionQueue) { () -> Void in
            self.stopRecordWithCompletionHandler { () -> Void in
                self.cropVideoSquare()
            }
        }
    }
    
    func videoControls(controls: MudVideoControls,cancelDidSelected sendr: AnyObject?) {
        dispatch_async(self.sessionQueue) { () -> Void in
            self.stopRecordWithCompletionHandler { () -> Void in
                self.deleteFile(self.tmpVideoCacheURL)
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    self.dismissViewControllerAnimated(true, completion: { () -> Void in
                    })
                })
            }
        }
      
    }
    
    func videoControls(controls: MudVideoControls,deleteDidSelected sendr: AnyObject?) {
        if self.writing == false {
            self.controls.updateProgressView(0)
            self.deleteFile(self.tmpVideoCacheURL)
            self.currentFrame = 0
        }
    }
    
    func videoControls(controls: MudVideoControls,cameraChangeDidSelected sendr: AnyObject?) {
        
    }
    
    func videoControls(controls: MudVideoControls,flashModeChangeDidSelected sendr: AnyObject?) {

    }
}

extension MudVideoRecordViewController: AVCaptureAudioDataOutputSampleBufferDelegate,AVCaptureVideoDataOutputSampleBufferDelegate {
    
    //MARK: - Delegate
    public func captureOutput(captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
        if self.writing {
            if self.assetWriter == nil {
                if self.initAssetWriterWithFormatDescription(CMSampleBufferGetFormatDescription(sampleBuffer)!) == false {
                    NSLog("AssetWriter init error")
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
                        NSLog("%@",self.assetWriter.error!.userInfo)
                    }
                } else {
                    //hand error
                }
                self.currentFrame++
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    //update progress
                    let progress = Float(self.currentFrame)/Float(self.maxFrame)
                    self.controls.updateProgressView(progress)
                    if self.currentFrame >= self.maxFrame {
                        self.stopRecordWithCompletionHandler({ () -> Void in
                            self.cropVideoSquare()
                        })
                    }
                })
                
            } else if captureOutput == self.audioOutput {
                if (self.assetWriter.status.rawValue > AVAssetWriterStatus.Writing.rawValue) {
                    if (self.assetWriter.status == AVAssetWriterStatus.Failed) {
                        return
                    }
                }
                if self.audioAssetWriterInput.readyForMoreMediaData && sbufWithNewTiming != nil {
                    if self.audioAssetWriterInput.appendSampleBuffer(sbufWithNewTiming!) {
                        NSLog("audio success")
                    }
                }
            }
        }
    }
    
    private func stopRecordWithCompletionHandler(handler: () -> Void) {
        if self.running == false {
            return
        }
        self.running = false
        self.session.stopRunning()
        if self.assetWriter != nil {
            self.videoAssetWriterInput.markAsFinished()
            self.assetWriter.finishWritingWithCompletionHandler({ () -> Void in
                if self.assetWriter.status == AVAssetWriterStatus.Completed {
                    self.videoAssetWriterInput = nil;
                    self.assetWriter = nil;
                    handler()
                }
            })
        }
    }
    
    private func cropVideoSquare() {
        
        //load our movie Asset
        let asset = AVAsset(URL: self.tmpVideoCacheURL)
        
        //create an avassetrack with our asset
        let clipVideoTrack = asset.tracksWithMediaType(AVMediaTypeVideo)[0]
        
        //create a video composition and preset some settings
        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTimeMake(1, 30)
        //here we are setting its render size to its height x height (Square)
        videoComposition.renderSize = CGSizeMake(clipVideoTrack.naturalSize.height,clipVideoTrack.naturalSize.height*0.75);
        
        //create a video instruction
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRangeMake(kCMTimeZero, CMTimeMakeWithSeconds(60, 30));
        
        let transformer = AVMutableVideoCompositionLayerInstruction(assetTrack: clipVideoTrack)
        
        //Here we shift the viewing square up to the TOP of the video so we only see the top
        let t1 = CGAffineTransformMakeTranslation(clipVideoTrack.naturalSize.height, -64)
        
        //Use this code if you want the viewing square to be in the middle of the video
        //CGAffineTransform t1 = CGAffineTransformMakeTranslation(clipVideoTrack.naturalSize.height, -(clipVideoTrack.naturalSize.width - clipVideoTrack.naturalSize.height) /2 );
        
        //Make sure the square is portrait
        let t2 = CGAffineTransformRotate(t1, CGFloat(M_PI_2))
        
        let finalTransform = t2
        transformer.setTransform(finalTransform, atTime: kCMTimeZero)
        
        //add the transformer layer instructions, then add to video composition
        instruction.layerInstructions = [transformer]
        videoComposition.instructions = [instruction]
    
        //Remove any prevouis videos at that path
        self.deleteFile(self.videoFileCacheURL)
        
        //Export
        let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality)
        exporter?.videoComposition = videoComposition
        exporter?.outputURL = self.videoFileCacheURL
        exporter?.outputFileType = AVFileTypeMPEG4
        exporter?.exportAsynchronouslyWithCompletionHandler({ () -> Void in
            self.deleteFile(self.tmpVideoCacheURL)
            let library = ALAssetsLibrary()
            if library.videoAtPathIsCompatibleWithSavedPhotosAlbum(self.videoFileCacheURL) {
                library.writeVideoAtPathToSavedPhotosAlbum(self.videoFileCacheURL, completionBlock: { (assetURL, error) -> Void in
                    
                })
            }
            
        })
    }
}

public extension MudVideoRecordViewController {
    public func deleteFile(fileURL: NSURL)->Bool {
        do {
            try NSFileManager.defaultManager().removeItemAtURL(fileURL)
            return true
        } catch _ as NSError {
            return false
        }
    }
}
