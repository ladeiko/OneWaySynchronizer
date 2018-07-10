//
//  ViewController.swift
//  OneWaySynchronizerDemo
//
//  Created by Siarhei Ladzeika on 7/7/18.
//  Copyright © 2018 Siarhei Ladzeika. All rights reserved.
//

import UIKit

class Cell: UITableViewCell {
    var key: String?
    
    override func prepareForReuse() {
        super.prepareForReuse()
        key = nil
        textLabel?.text = nil
        imageView?.image = nil
    }
}

class ViewController: UIViewController, UITableViewDataSource {
    
    let service = MyService()
    
    @IBOutlet weak var tableView: UITableView?
    @IBOutlet weak var activitiView: UIActivityIndicatorView?

    override func viewDidLoad() {
        super.viewDidLoad()
        self.activitiView?.layer.cornerRadius = 5
        self.activitiView?.transform = CGAffineTransform(scaleX: 2, y: 2)
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(self.sync))
        sync()
    }
    
    @IBAction
    func sync() {
        navigationItem.rightBarButtonItem?.isEnabled = false
        self.tableView?.isHidden = true
        self.activitiView?.isHidden = false
        self.activitiView?.startAnimating()
        
        service.sync { (error) in
            
            self.tableView?.reloadData()
            self.activitiView?.stopAnimating()
            self.activitiView?.isHidden = true
            self.tableView?.isHidden = false
            self.navigationItem.rightBarButtonItem?.isEnabled = true
            
            if let error = error {
                let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
                self.present(alert, animated: true, completion: nil)
            }
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return service.count()
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Default") as! Cell
        cell.textLabel?.text = service.title(at: indexPath.row)
        let key = service.key(at: indexPath.row)
        cell.detailTextLabel?.text = key
        cell.key = key
        service.preview(at: indexPath.row) { (_, image) in
            if cell.key == key {
                let imageView = UIImageView(image: image)
                imageView.frame = CGRect(x: 0, y: 0, width: 35, height: 35)
                cell.accessoryView = imageView
            }
        }
        return cell
    }
    
}

