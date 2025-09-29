import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="template-filter"
export default class extends Controller {
  static targets = ["searchInput"]
  static values = {
    debounceDelay: { type: Number, default: 500 }
  }

  connect() {
    this.searchTimeout = null
  }

  disconnect() {
    if (this.searchTimeout) {
      clearTimeout(this.searchTimeout)
    }
  }

  // Handle search input with debouncing and URL navigation
  search() {
    if (this.searchTimeout) {
      clearTimeout(this.searchTimeout)
    }

    this.searchTimeout = setTimeout(() => {
      this.navigateWithSearch()
    }, this.debounceDelayValue)
  }

  // Clear search and navigate
  clearSearch() {
    this.searchInputTarget.value = ""
    this.navigateWithSearch()
  }

  // Navigate to new URL with search parameter
  navigateWithSearch() {
    const url = new URL(window.location)
    const searchQuery = this.searchInputTarget.value.trim()

    if (searchQuery) {
      url.searchParams.set('search', searchQuery)
    } else {
      url.searchParams.delete('search')
    }

    // Navigate to the new URL
    window.location.href = url.toString()
  }
}
