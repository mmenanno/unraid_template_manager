import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="community-sync"
export default class extends Controller {
  static targets = ["communitySection"]

  connect() {
    this.toggleCommunitySync()
  }

  toggleCommunitySync() {
    const checkbox = this.element.querySelector("#not_in_community_checkbox")
    const communitySection = document.getElementById("community_matching_section")

    if (checkbox && communitySection) {
      if (checkbox.checked) {
        communitySection.classList.add("hidden")
      } else {
        communitySection.classList.remove("hidden")
      }
    }
  }
}
