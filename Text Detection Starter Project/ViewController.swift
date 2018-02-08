//
//  ViewController.swift
//
//  Created by Tom Dowding on 06/02/2018.
//  Copyright © 2018 Tom Dowding. All rights reserved.
//

import UIKit
import SnapKit

class ViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.addSubview(resultsLabel)
        resultsLabel.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(10)
            make.right.equalToSuperview().inset(10)
            make.bottom.equalToSuperview()
            make.height.equalTo(60)
        }
        
        self.view.addSubview(cameraImageView)
        cameraImageView.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
            make.bottom.equalTo(resultsLabel.snp.top)
        }
        
   
        cameraTextRecognizer = CameraTextRecognizer(cameraImageView: cameraImageView)
        cameraTextRecognizer?.delegate = self
        cameraTextRecognizer?.highlightWords = false
        cameraTextRecognizer?.start()
    }

    override func viewDidLayoutSubviews() {
        cameraImageView.layer.sublayers?[0].frame = cameraImageView.bounds
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    // MARK: - Private
    private var cameraTextRecognizer: CameraTextRecognizer?
    
    private lazy var cameraImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.backgroundColor = .clear
        imageView.contentMode = .center
        return imageView
    }()
    
    private lazy var resultsLabel: UILabel = {
        let label = UILabel()
        label.backgroundColor = .white
        label.textColor = .black
        label.font = UIFont.systemFont(ofSize: 20)
        label.textAlignment = .center
        return label
    }()
}

extension ViewController: TextRecognizerDelegate {
    func didRecognizeWords(_ words: [String]) {
        resultsLabel.text = "\(words)"
    }
}

