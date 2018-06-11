/*
 Copyright © 2017 Apple Inc.
 
 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 
Abstract:
Utility class for showing messages above the AR view.
*/

import Foundation
import ARKit

enum MessageType {
	case trackingStateEscalation
	case planeEstimation
	case contentPlacement
	case focusSquare
    case general
}

@available(iOS 11.0, *)
class VirtualGoalTextManager {
	
	init(viewController: VirtualGoalViewController) {
		self.viewController = viewController
	}
	
	func showMessage(_ text: String, autoHide: Bool = true) {
		// cancel any previous hide timer
		messageHideTimer?.invalidate()
		
		// set text
		viewController.messageLabel.text = text
		
		// make sure status is showing
		showHideMessage(hide: false, animated: true)
		
		if autoHide {
			// Compute an appropriate amount of time to display the on screen message.
			// According to https://en.wikipedia.org/wiki/Words_per_minute, adults read
			// about 200 words per minute and the average English word is 5 characters
			// long. So 1000 characters per minute / 60 = 15 characters per second.
			// We limit the duration to a range of 1-10 seconds.
			let charCount = text.characters.count
			let displayDuration: TimeInterval = min(10, Double(charCount) / 15.0 + 1.0)
			messageHideTimer = Timer.scheduledTimer(withTimeInterval: displayDuration,
			                                        repeats: false,
			                                        block: { [weak self] ( _ ) in
														self?.showHideMessage(hide: true, animated: true)
			})
		}
	}
	
    func showDebugMessage(_ message: String) {
        guard viewController.showDetailedMessages else {
            return
        }
        
        // cancel any previous hide timer
        debugMessageHideTimer?.invalidate()
        
        // set text
        DispatchQueue.main.async {
            self.viewController.debugMessageLabel.text = message
        }
        
        // make sure debug message is showing
        showHideDebugMessage(hide: false, animated: true)
        
        // Compute an appropriate amount of time to display the on screen message.
        // According to https://en.wikipedia.org/wiki/Words_per_minute, adults read
        // about 200 words per minute and the average English word is 5 characters
        // long. So 1000 characters per minute / 60 = 15 characters per second.
        // We limit the duration to a range of 1-10 seconds.
        let charCount = message.characters.count
        let displayDuration: TimeInterval = min(10, Double(charCount) / 15.0 + 1.0)
        debugMessageHideTimer = Timer.scheduledTimer(withTimeInterval: displayDuration,
                                                     repeats: false,
                                                     block: { [weak self] ( _ ) in
                                                        self?.showHideDebugMessage(hide: true, animated: true)
        })
    }
	
	var schedulingMessagesBlocked = false
	
	func scheduleMessage(_ text: String, inSeconds seconds: TimeInterval, messageType: MessageType) {
		// Do not schedule a new message if a feedback escalation alert is still on screen.
		guard !schedulingMessagesBlocked else {
			return
		}
		
		var timer: Timer?
		switch messageType {
		case .contentPlacement: timer = contentPlacementMessageTimer
		case .focusSquare: timer = focusSquareMessageTimer
		case .planeEstimation: timer = planeEstimationMessageTimer
		case .trackingStateEscalation: timer = trackingStateFeedbackEscalationTimer
        case .general: timer = generalMessageTimer
		}
		
		if timer != nil {
			timer!.invalidate()
			timer = nil
		}
		timer = Timer.scheduledTimer(withTimeInterval: seconds,
		                             repeats: false,
		                             block: { [weak self] ( _ ) in
										self?.showMessage(text)
										timer?.invalidate()
										timer = nil
		})
		switch messageType {
		case .contentPlacement: contentPlacementMessageTimer = timer
		case .focusSquare: focusSquareMessageTimer = timer
		case .planeEstimation: planeEstimationMessageTimer = timer
		case .trackingStateEscalation: trackingStateFeedbackEscalationTimer = timer
        case .general: trackingStateFeedbackEscalationTimer = timer
		}
	}
	
	func showTrackingQualityInfo(for trackingState: ARCamera.TrackingState, autoHide: Bool) {
		showMessage(trackingState.presentationString, autoHide: autoHide)
	}
	
	func escalateFeedback(for trackingState: ARCamera.TrackingState, inSeconds seconds: TimeInterval) {
		if self.trackingStateFeedbackEscalationTimer != nil {
			self.trackingStateFeedbackEscalationTimer!.invalidate()
			self.trackingStateFeedbackEscalationTimer = nil
		}
		
		self.trackingStateFeedbackEscalationTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false, block: { _ in
			self.trackingStateFeedbackEscalationTimer?.invalidate()
			self.trackingStateFeedbackEscalationTimer = nil
			self.schedulingMessagesBlocked = true
			var title = ""
			var message = ""
			switch trackingState {
			case .notAvailable:
				title = "Tracking status: Not available."
				message = "Tracking status has been unavailable for an extended time. Try resetting the session."
			case .limited(let reason):
				title = "Tracking status: Limited."
				message = "Tracking status has been limited for an extended time. "
				switch reason {
				case .excessiveMotion: message += "Try slowing down your movement, or reset the session."
				case .insufficientFeatures: message += "Try pointing at a flat surface, or reset the session."
                case .initializing: message += "Initializing. Please wait."
                }
			case .normal: break
			}
			
			let restartAction = UIAlertAction(title: "Reset", style: .destructive, handler: { _ in
				self.viewController.restartExperience(self)
				self.schedulingMessagesBlocked = false
			})
			let okAction = UIAlertAction(title: "OK", style: .default, handler: { _ in
				self.schedulingMessagesBlocked = false
			})
			self.showAlert(title: title, message: message, actions: [restartAction, okAction])
		})
	}
	
	func cancelScheduledMessage(forType messageType: MessageType) {
		var timer: Timer?
		switch messageType {
		case .contentPlacement: timer = contentPlacementMessageTimer
		case .focusSquare: timer = focusSquareMessageTimer
		case .planeEstimation: timer = planeEstimationMessageTimer
		case .trackingStateEscalation: timer = trackingStateFeedbackEscalationTimer
        case .general: timer = generalMessageTimer
		}
		
		if timer != nil {
			timer!.invalidate()
			timer = nil
		}
	}
	
	func cancelAllScheduledMessages() {
		cancelScheduledMessage(forType: .contentPlacement)
		cancelScheduledMessage(forType: .planeEstimation)
		cancelScheduledMessage(forType: .trackingStateEscalation)
		cancelScheduledMessage(forType: .focusSquare)
	}
	
	var alertController: UIAlertController?
	
	func showAlert(title: String, message: String, actions: [UIAlertAction]? = nil) {
		alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
		if let actions = actions {
			for action in actions {
				alertController!.addAction(action)
			}
		} else {
			alertController!.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
		}
		self.viewController.present(alertController!, animated: true, completion: nil)
	}
	
	func dismissPresentedAlert() {
		alertController?.dismiss(animated: true, completion: nil)
	}
	
	let blurEffectViewTag = 100
	
	func blurBackground() {
		let blurEffect = UIBlurEffect(style: UIBlurEffectStyle.light)
		let blurEffectView = UIVisualEffectView(effect: blurEffect)
		blurEffectView.frame = viewController.view.bounds
		blurEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		blurEffectView.tag = blurEffectViewTag
		viewController.view.addSubview(blurEffectView)
	}
	
	func unblurBackground() {
		for view in viewController.view.subviews {
			if let blurView = view as? UIVisualEffectView, blurView.tag == blurEffectViewTag {
				blurView.removeFromSuperview()
			}
		}
	}
	
	// MARK: - Private
	private var viewController: VirtualGoalViewController!
	
	// Timers for hiding regular and debug messages
	private var messageHideTimer: Timer?
    private var debugMessageHideTimer: Timer?
	
	// Timers for showing scheduled messages
	private var focusSquareMessageTimer: Timer?
	private var planeEstimationMessageTimer: Timer?
	private var contentPlacementMessageTimer: Timer?
	
	// Timer for tracking state escalation
	private var trackingStateFeedbackEscalationTimer: Timer?
	
    private var generalMessageTimer: Timer?

	private func showHideMessage(hide: Bool, animated: Bool) {
		if !animated {
			viewController.messageLabel.isHidden = hide
			return
		}
		
		UIView.animate(withDuration: 0.2,
		               delay: 0,
		               options: [.allowUserInteraction, .beginFromCurrentState],
		               animations: {
						self.viewController.messageLabel.isHidden = hide
						self.updateMessagePanelVisibility()
		}, completion: nil)
	}
	
    private func showHideDebugMessage(hide: Bool, animated: Bool) {
        DispatchQueue.main.async {
            
            if !animated {
                self.viewController.debugMessageLabel.isHidden = hide
                return
            }
            
            
            UIView.animate(withDuration: 0.2,
                           delay: 0,
                           options: [.allowUserInteraction, .beginFromCurrentState],
                           animations: {
                            self.viewController.debugMessageLabel.isHidden = hide
                            self.updateMessagePanelVisibility()
                            
            }
                
                , completion: nil)
        }
    }
	
	private func updateMessagePanelVisibility() {
        DispatchQueue.main.async {
            // Show and hide the panel depending whether there is something to show.
            self.viewController.messagePanel.isHidden = self.viewController.messageLabel.isHidden &&
                self.viewController.debugMessageLabel.isHidden &&
                self.viewController.featurePointCountLabel.isHidden
        }
		
 }
}
