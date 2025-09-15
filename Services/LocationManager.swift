import Foundation
import CoreLocation

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
  @Published var status: CLAuthorizationStatus?
  @Published var lastLocation: CLLocation?

  private let manager = CLLocationManager()

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
  }

  func requestWhenInUse() {
    manager.requestWhenInUseAuthorization()
    manager.startUpdatingLocation()
  }

  func stop() { manager.stopUpdatingLocation() }

  // MARK: - CLLocationManagerDelegate
  func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
    DispatchQueue.main.async { self.status = status }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let loc = locations.last else { return }
    DispatchQueue.main.async { self.lastLocation = loc }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    print("[Location] error: \(error)")
  }
}

