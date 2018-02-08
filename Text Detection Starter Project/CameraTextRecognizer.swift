//
//  TextRecognizer.swift
//
//  Created by Tom Dowding on 06/02/2018.
//  Copyright © 2018 Tom Dowding. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation
import Vision
import CoreML

protocol TextRecognizerDelegate: class {
    func didRecognizeWords(_ words: [String])
}

class CameraTextRecognizer: NSObject {
  
    // MARK: - Public
    weak var delegate: TextRecognizerDelegate?
    var highlightWords: Bool = false
    
    init(cameraImageView: UIImageView) {
        self.cameraImageView = cameraImageView
    }
    
    func start() {
        startLiveVideo()
    }
    
    // MARK: - Private
    private let session = AVCaptureSession()
    private let cameraImageView: UIImageView
    private var inputImage: CIImage?
    private var allRecognizedWords:[String] = [String]()
    private var currentRecognizedWord:String = String()
    
    // MARK: - Start live video feed
    private func startLiveVideo() {
        
        // Setup our capture session
        session.sessionPreset = AVCaptureSession.Preset.photo
        
        // Create a capture device with AVMediaType as video because we want a live stream
        let captureDevice = AVCaptureDevice.default(for: AVMediaType.video)
        
        // Add session input as the capture device input
        let deviceInput = try! AVCaptureDeviceInput(device: captureDevice!)
        session.addInput(deviceInput)
        
        // The session output is what the video should appear as.
        // We want the video to appear as a kCVPixelFormatType_32BGR
        let deviceOutput = AVCaptureVideoDataOutput()
        deviceOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        deviceOutput.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: DispatchQoS.QoSClass.default))
        session.addOutput(deviceOutput)
        
        // Add the video preview to the imageView so we can see it
        let imageLayer = AVCaptureVideoPreviewLayer(session: session)
        imageLayer.frame = cameraImageView.bounds
        cameraImageView.layer.addSublayer(imageLayer)
        
        // Get the session running
        // Things will happen when our sample buffer delegate (self) reports output
        session.startRunning()
    }
    
    // MARK: - Text detection
    private lazy var textDetectionRequest: VNDetectTextRectanglesRequest = {
        let textDetectionRequest = VNDetectTextRectanglesRequest(completionHandler: self.textDetectionResponse)
        textDetectionRequest.reportCharacterBoxes = true
        textDetectionRequest.preferBackgroundProcessing = false
        return textDetectionRequest
    }()
    
    private func textDetectionResponse(request: VNRequest, error: Error?) {
        guard let observations = request.results as? [VNTextObservation] else { print("Unexpected text detection result"); return }
        guard let inputImage = self.inputImage else { return }
        
        // Empty overall results
        allRecognizedWords = [String]()
        
        // A text observation is like a word
        for textObservation: VNTextObservation in observations {
            
            // The character boxes are the positions in the original image (scaled from 0.0 -> 1.0)
            guard let boxes = textObservation.characterBoxes else { continue }
            
            // Get the transform from box space to image space
            let transform = CGAffineTransform.identity.scaledBy(x: inputImage.extent.size.width, y: inputImage.extent.size.height)
          
            // Empty region results
            currentRecognizedWord = ""
            
            // Go through each character box and input into OCR
            for box in boxes {
                
                // Scale the box's bounding box points to the image pixels
                let realBoundingBox = box.boundingBox.applying(transform)
     
                // Check the bounding box is within the image
                guard inputImage.extent.contains(realBoundingBox) else { print("Invalid detected rectangle"); return}
                
                // Scale the box's points to the image pixels
                let topleft = box.topLeft.applying(transform)
                let topright = box.topRight.applying(transform)
                let bottomleft = box.bottomLeft.applying(transform)
                let bottomright = box.bottomRight.applying(transform)
            
                // Crop and rectify the input image to get the character image
                let charImage = inputImage
                    .cropped(to: realBoundingBox)
                    .applyingFilter("CIPerspectiveCorrection", parameters: [
                        "inputTopLeft" : CIVector(cgPoint: topleft),
                        "inputTopRight" : CIVector(cgPoint: topright),
                        "inputBottomLeft" : CIVector(cgPoint: bottomleft),
                        "inputBottomRight" : CIVector(cgPoint: bottomright)
                        ])
     
                // Handler for OCR request
                let imageRequestHandler = VNImageRequestHandler(ciImage: charImage, options: [:])
                do {
                    try imageRequestHandler.perform([self.ocrRequest])
                }  catch { print("Error")}
            }
            
            // Append recognized word to array
            allRecognizedWords.append(currentRecognizedWord)
        }
        
        // Output results
        DispatchQueue.main.async() {
            
            // Highlight the boxes
            if self.highlightWords {
                self.cameraImageView.layer.sublayers?.removeSubrange(1...)
                for textObservation in observations {
                    self.highlightWord(textObservation: textObservation)
                }
            }
            
            // Tell delegate we found some words
            self.delegate?.didRecognizeWords(self.allRecognizedWords)
        }
    }
    
    private func highlightWord(textObservation: VNTextObservation) {
        guard let boxes = textObservation.characterBoxes else {
            return
        }
        
        var maxX: CGFloat = 9999.0
        var minX: CGFloat = 0.0
        var maxY: CGFloat = 9999.0
        var minY: CGFloat = 0.0
        
        for char in boxes {
            if char.bottomLeft.x < maxX {
                maxX = char.bottomLeft.x
            }
            if char.bottomRight.x > minX {
                minX = char.bottomRight.x
            }
            if char.bottomRight.y < maxY {
                maxY = char.bottomRight.y
            }
            if char.topRight.y > minY {
                minY = char.topRight.y
            }
        }
        
        let xCord = maxX * cameraImageView.frame.size.width
        let yCord = (1 - minY) * cameraImageView.frame.size.height
        let width = (minX - maxX) * cameraImageView.frame.size.width
        let height = (minY - maxY) * cameraImageView.frame.size.height
        
        let outline = CALayer()
        outline.frame = CGRect(x: xCord, y: yCord, width: width, height: height)
        outline.borderWidth = 2.0
        outline.borderColor = UIColor.red.cgColor
        
        cameraImageView.layer.addSublayer(outline)
    }
    
    // MARK: - OCR
    private lazy var ocrRequest: VNCoreMLRequest = {
        do {
            let model = try VNCoreMLModel(for:OCR().model)
            let coreMLRequest = VNCoreMLRequest(model: model, completionHandler: self.ocrRequestResponse)
            coreMLRequest.imageCropAndScaleOption = .scaleFill
            return coreMLRequest
        } catch {
            fatalError("Cannot load OCR model")
        }
    }()
    
    private func ocrRequestResponse(request: VNRequest, error: Error?) {
        guard let results = request.results as? [VNClassificationObservation] else { print("OCR unexpected result"); return }
        guard let best = results.first else { print("OCR can't get best result"); return }
        currentRecognizedWord = currentRecognizedWord.appending(best.identifier)
    }
}
    
// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraTextRecognizer: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        // Get pixel buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        // Set the input image. After text detection, regions of this image matching located characters will be passed in to OCR
        self.inputImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        
        // Make text detection request options with the camera data
        var textDetectionRequestHandlerOptions:[VNImageOption : Any] = [:]
        if let camData = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, nil) {
            textDetectionRequestHandlerOptions = [.cameraIntrinsics:camData]
        }
        
        // Make text detection request handler with our pixel buffer and options
        let textDetectionRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: textDetectionRequestHandlerOptions)
        
        // Run with our text detection request
        do {
            try textDetectionRequestHandler.perform([self.textDetectionRequest])
        } catch {
            print(error)
        }
    }
}
