//
//  AlertPresenter.swift
//  StikDebug
//

import UIKit

func showAlert(
    title: String,
    message: String,
    showOk: Bool,
    showTryAgain: Bool = false,
    primaryButtonText: String? = nil,
    completion: ((Bool) -> Void)? = nil
) {
    DispatchQueue.main.async {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController else { return }

        var top: UIViewController? = root
        while let presented = top?.presentedViewController {
            top = presented
        }

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        if showTryAgain {
            alert.addAction(UIAlertAction(title: primaryButtonText ?? "Try Again", style: .default) { _ in
                completion?(true)
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                completion?(false)
            })
        } else {
            alert.addAction(UIAlertAction(title: primaryButtonText ?? "OK", style: .default) { _ in
                completion?(true)
            })
        }
        top?.present(alert, animated: true)
    }
}
