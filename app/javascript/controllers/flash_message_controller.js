import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    autoDismiss: { type: Boolean, default: true },
    delay: { type: Number, default: 5000 }
  }

  connect() {
    if (this.autoDismissValue) {
      this.scheduleAutoDismiss()
    }
  }

  scheduleAutoDismiss() {
    this.timeout = setTimeout(() => {
      this.dismiss()
    }, this.delayValue)
  }

  dismiss() {
    // Clear any pending timeout
    if (this.timeout) {
      clearTimeout(this.timeout)
    }

    // Fade out animation
    this.element.style.transition = 'opacity 0.3s ease-out, transform 0.3s ease-out'
    this.element.style.opacity = '0'
    this.element.style.transform = 'translateY(-10px)'

    // Remove from DOM after animation
    setTimeout(() => {
      if (this.element.parentNode) {
        this.element.parentNode.removeChild(this.element)
      }
    }, 300)
  }

  // Allow manual dismissal by clicking
  manualDismiss() {
    this.dismiss()
  }

  disconnect() {
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
  }
}
