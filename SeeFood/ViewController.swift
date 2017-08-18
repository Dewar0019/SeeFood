//
//  ViewController.swift
//  SeeFood
//
//  Created by Dewar Tan on 8/4/17.
//  Copyright © 2017 dewar. All rights reserved.
//

import UIKit
import SwiftyJSON

class ViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

  @IBOutlet weak var imageView: UIImageView!
  let imagePicker = UIImagePickerController()
  let session = URLSession.shared

  @IBOutlet weak var emotionStatus: UITextField!
  var googleAPIKey = ""
  var googleURL: URL {
    return URL(string: "https://vision.googleapis.com/v1/images:annotate?key=\(googleAPIKey)")!
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    // Do any additional setup after loading the view, typically from a nib.
  }

  @IBAction func analyzeImage(_ sender: Any) {
    if let pickedImage = imageView.image as? UIImage {
      imageView.contentMode = .scaleAspectFit
      imageView.isHidden = true // You could optionally display the image here by setting imageView.image = pickedImage
      //      spinner.startAnimating()
      emotionStatus.isHidden = true

      // Base64 encode the image and create the request
      let binaryImageData = base64EncodeImage(pickedImage)
      createRequest(with: binaryImageData)
    }
  }

  func base64EncodeImage(_ image: UIImage) -> String {
    var imagedata = UIImagePNGRepresentation(image)

    // Resize the image if it exceeds the 2MB API limit
    if ((imagedata?.count)! > 2097152) {
      let oldSize: CGSize = image.size
      let newSize: CGSize = CGSize(width: 800, height: oldSize.height / oldSize.width * 800)
      imagedata = resizeImage(newSize, image: image)
    }
    return imagedata!.base64EncodedString(options: .endLineWithCarriageReturn)
  }


  func resizeImage(_ imageSize: CGSize, image: UIImage) -> Data {
    UIGraphicsBeginImageContext(imageSize)
    image.draw(in: CGRect(x: 0, y: 0, width: imageSize.width, height: imageSize.height))
    let newImage = UIGraphicsGetImageFromCurrentImageContext()
    let resizedImage = UIImagePNGRepresentation(newImage!)
    UIGraphicsEndImageContext()
    return resizedImage!
  }


  func createRequest(with imageBase64: String) {
    // Create our request URL

    var request = URLRequest(url: googleURL)
    request.httpMethod = "POST"
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.addValue(Bundle.main.bundleIdentifier ?? "", forHTTPHeaderField: "X-Ios-Bundle-Identifier")

    // Build our API request
    let jsonRequest = [
      "requests": [
        "image": [
          "content": imageBase64
        ],
        "features": [
          [
            "type": "FACE_DETECTION",
            "maxResults": 10
          ],
          [
            "type": "LABEL_DETECTION",
            "maxResults": 10
          ]
        ]
      ]
    ]
    let jsonObject = JSON(jsonDictionary: jsonRequest)

    // Serialize the JSON
    guard let data = try? jsonObject.rawData() else {
      return
    }

    request.httpBody = data

    // Run the request on a background thread
    DispatchQueue.global().async { self.runRequestOnBackgroundThread(request) }
  }

  func runRequestOnBackgroundThread(_ request: URLRequest) {
    // run the request
    let task: URLSessionDataTask = session.dataTask(with: request) { (data, response, error) in
      guard let data = data, error == nil else {
        print(error?.localizedDescription ?? "")
        return
      }
      self.analyzeResults(data)
    }
    task.resume()
  }


  @IBAction func openCameraButton(_ sender: Any) {
    if UIImagePickerController.isSourceTypeAvailable(UIImagePickerControllerSourceType.camera) {
      imagePicker.delegate = self
      imagePicker.sourceType = UIImagePickerControllerSourceType.camera;
      imagePicker.allowsEditing = false
      imagePicker.cameraCaptureMode = .photo
      self.present(imagePicker, animated: true, completion: nil)

    }
  }

  func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
    self.imageView.isHidden = false
    imagePicker.dismiss(animated: true, completion: nil)
    imageView.image = info[UIImagePickerControllerOriginalImage] as! UIImage
    self.emotionStatus.isHidden = true
    self.emotionStatus.text = ""
  }



  func analyzeResults(_ dataToParse: Data) {

    // Update UI on the main thread
    DispatchQueue.main.async(execute: {


      // Use SwiftyJSON to parse results
      let json = JSON(data: dataToParse)
      let errorObj: JSON = json["error"]

      //      self.spinner.stopAnimating()
      self.imageView.isHidden = false
      self.emotionStatus.isHidden = false
      self.emotionStatus.text = ""

      // Check for errors
      if (errorObj.dictionaryValue != [:]) {
        //        self.labelResults.text = "Error code \(errorObj["code"]): \(errorObj["message"])"
      } else {
        // Parse the response
        print(json)
        let responses: JSON = json["responses"][0]

        // Get face annotations
        let faceAnnotations: JSON = responses["faceAnnotations"]
        let labelAnnotations = responses["labelAnnotations"][0]
        if faceAnnotations != nil {
          let emotions: Array<String> = ["joy", "sorrow", "surprise", "anger"]

          let numPeopleDetected:Int = faceAnnotations.count

          //          self.faceResults.text = "People detected: \(numPeopleDetected)\n\nEmotions detected:\n"

          var emotionTotals: [String: Double] = ["sorrow": 0, "joy": 0, "surprise": 0, "anger": 0]
          var emotionLikelihoods: [String: Double] = ["VERY_LIKELY": 0.9, "LIKELY": 0.75, "POSSIBLE": 0.5, "UNLIKELY":0.25, "VERY_UNLIKELY": 0.0]

          for index in 0..<numPeopleDetected {
            let personData:JSON = faceAnnotations[index]

            // Sum all the detected emotions
            for emotion in emotions {
              let lookup = emotion + "Likelihood"
              let result:String = personData[lookup].stringValue
              emotionTotals[emotion]! += emotionLikelihoods[result]!
            }
          }
          // Get emotion likelihood as a % and display in UI
          for (emotion, total) in emotionTotals {
            let likelihood:Double = total / Double(numPeopleDetected)
            let percent: Int = Int(round(likelihood * 100))
            self.emotionStatus.text! += "\(emotion): \(percent)%\n"
          }
        } else if labelAnnotations != nil && Float(labelAnnotations["score"].floatValue) > 0.65 {

          self.emotionStatus.text = "object:\(labelAnnotations["description"]) score:\(labelAnnotations["score"])"
        } else {
          self.emotionStatus.text = "No face or object accurately detected"
        }
      }
    })
  }
  
  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    // Dispose of any resources that can be recreated.
  }
  
  
}

