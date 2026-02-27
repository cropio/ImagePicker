import Foundation
import UIKit
import Photos

extension Bundle {
    static func myResourceBundle() -> Bundle? {
        let bundles = Bundle.allBundles
        let bundlePaths = bundles.compactMap { $0.resourceURL?.appendingPathComponent("ImagePicker", isDirectory: false).appendingPathExtension("bundle") }

        return bundlePaths.compactMap({ Bundle(url: $0) }).first
    }
}

open class AssetManager {

  public static func getImage(_ name: String) -> UIImage {
    let traitCollection = UITraitCollection(displayScale: 3)
    var bundle = Bundle.myResourceBundle()

    if let resource = bundle?.resourcePath, let resourceBundle = Bundle(path: resource + "/ImagePicker.bundle") {
      bundle = resourceBundle
    }

    return UIImage(named: name, in: bundle, compatibleWith: traitCollection) ?? UIImage()
  }

  public static func fetch(withConfiguration configuration: ImagePickerConfiguration, _ completion: @escaping (_ assets: [PHAsset]) -> Void) {
    guard PHPhotoLibrary.authorizationStatus() == .authorized else { return }

    let options = PHFetchOptions()
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

    DispatchQueue.global(qos: .background).async {
      let fetchResult = configuration.allowVideoSelection
        ? PHAsset.fetchAssets(with: options)
        : PHAsset.fetchAssets(with: .image, options: options)

      if fetchResult.count > 0 {
        var assets = [PHAsset]()
        fetchResult.enumerateObjects({ object, _, _ in
          assets.insert(object, at: 0)
        })

        DispatchQueue.main.async {
          completion(assets)
        }
      }
    }
  }

  public static func resolveAsset(_ asset: PHAsset, size: CGSize = CGSize(width: 720, height: 1280), shouldPreferLowRes: Bool = false, completion: @escaping (_ image: UIImage?) -> Void) {
    let imageManager = PHImageManager.default()
    let requestOptions = PHImageRequestOptions()
    requestOptions.deliveryMode = shouldPreferLowRes ? .fastFormat : .highQualityFormat
    requestOptions.isNetworkAccessAllowed = true

    imageManager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: requestOptions) { image, info in
      let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
      guard !isDegraded else { return }
      DispatchQueue.main.async {
        completion(image)
      }
    }
  }

  public static func resolveAssets(_ assets: [PHAsset], completion: @escaping (_ images: [Image]) -> Void) {
    let imageManager = PHImageManager.default()
    let requestOptions = PHImageRequestOptions()
    requestOptions.isNetworkAccessAllowed = true
    requestOptions.deliveryMode = .highQualityFormat

    let group = DispatchGroup()
    var indexedImages = [(index: Int, image: Image)]()
    let lock = NSLock()

    for (index, asset) in assets.enumerated() {
      group.enter()
      imageManager.requestImageData(for: asset, options: requestOptions) { data, name, _, _ in
        defer { group.leave() }
        guard let data = data, let name = name else { return }
        lock.lock()
        indexedImages.append((index, Image(data: data, name: name)))
        lock.unlock()
      }
    }

    group.notify(queue: .main) {
      completion(indexedImages.sorted { $0.index < $1.index }.map { $0.image })
    }
  }
}
