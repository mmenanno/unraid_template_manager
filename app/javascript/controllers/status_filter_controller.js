import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "menu", "text", "chevron"]

  connect() {
    console.log("Status filter dropdown controller connected")
    this.isOpen = false

    // Bind methods to preserve 'this' context
    this.boundCloseOnOutsideClick = this.closeOnOutsideClick.bind(this)
    this.boundCloseOnEscape = this.closeOnEscape.bind(this)
  }

  disconnect() {
    // Clean up event listeners
    document.removeEventListener('click', this.boundCloseOnOutsideClick)
    document.removeEventListener('keydown', this.boundCloseOnEscape)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()

    console.log("Status filter dropdown button clicked, current state:", this.isOpen)

    if (this.isOpen) {
      this.close()
    } else {
      this.open()
    }
  }

  selectOption(event) {
    event.preventDefault()
    event.stopPropagation()

    const filterValue = event.currentTarget.dataset.filter
    console.log("Status filter option selected:", filterValue)

    // Update URL and navigate
    const url = new URL(window.location)

    if (filterValue === 'all') {
      url.searchParams.delete('status_filter')
    } else {
      url.searchParams.set('status_filter', filterValue)
    }

    window.location.href = url.toString()
  }

  open() {
    console.log("Opening status filter dropdown")
    this.isOpen = true
    this.menuTarget.classList.remove('hidden')
    this.buttonTarget.setAttribute('aria-expanded', 'true')

    if (this.hasChevronTarget) {
      this.chevronTarget.style.transform = 'rotate(180deg)'
    }

    // Add event listeners for closing
    document.addEventListener('click', this.boundCloseOnOutsideClick)
    document.addEventListener('keydown', this.boundCloseOnEscape)
  }

  close() {
    console.log("Closing status filter dropdown")
    this.isOpen = false
    this.menuTarget.classList.add('hidden')
    this.buttonTarget.setAttribute('aria-expanded', 'false')

    if (this.hasChevronTarget) {
      this.chevronTarget.style.transform = 'rotate(0deg)'
    }

    // Remove event listeners
    document.removeEventListener('click', this.boundCloseOnOutsideClick)
    document.removeEventListener('keydown', this.boundCloseOnEscape)
  }

  closeOnOutsideClick(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  closeOnEscape(event) {
    if (event.key === 'Escape') {
      this.close()
    }
  }

  // Keyboard navigation
  navigateMenu(event) {
    const menuItems = Array.from(this.menuTarget.querySelectorAll('[data-action*="selectOption"]'))
    const currentIndex = menuItems.indexOf(document.activeElement)

    switch (event.key) {
      case 'ArrowDown':
        event.preventDefault()
        const nextIndex = (currentIndex + 1) % menuItems.length
        menuItems[nextIndex].focus()
        break
      case 'ArrowUp':
        event.preventDefault()
        const prevIndex = currentIndex > 0 ? currentIndex - 1 : menuItems.length - 1
        menuItems[prevIndex].focus()
        break
      case 'Enter':
      case ' ':
        event.preventDefault()
        document.activeElement.click()
        break
      case 'Tab':
        this.close()
        break
    }
  }
}
