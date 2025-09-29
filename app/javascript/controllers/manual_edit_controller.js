import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="manual-edit"
export default class extends Controller {
  static targets = ["editButton", "editInput", "originalValue", "radioButton"]
  static values = { fieldName: String, originalValue: String }

  connect() {
    this.updateVisibility()
  }

  // Called when radio button selection changes
  radioChanged() {
    this.updateVisibility()
  }

  // Show/hide edit button based on radio selection
  updateVisibility() {
    const isSelected = this.radioButtonTarget.checked

    if (isSelected) {
      this.editButtonTarget.classList.remove("hidden")
    } else {
      this.editButtonTarget.classList.add("hidden")
      this.cancelEdit() // Hide edit input if switching away
    }
  }

  // Show edit input and hide button
  showEdit() {
    this.editButtonTarget.classList.add("hidden")
    this.editInputTarget.classList.remove("hidden")
    this.editInputTarget.focus()

    // Set current value in input
    const currentValue = this.editInputTarget.querySelector("input").value || this.originalValueValue
    this.editInputTarget.querySelector("input").value = currentValue
  }

  // Hide edit input and show button
  cancelEdit() {
    this.editInputTarget.classList.add("hidden")
    this.editButtonTarget.classList.remove("hidden")
  }

  // Handle saving the edit
  saveEdit() {
    const inputValue = this.editInputTarget.querySelector("input").value

    // Update the displayed value
    this.originalValueTarget.textContent = inputValue

    // Hide edit input and show button
    this.cancelEdit()
  }

  // Handle key presses in edit input
  handleKeyPress(event) {
    if (event.key === "Enter") {
      this.saveEdit()
    } else if (event.key === "Escape") {
      this.cancelEdit()
    }
  }
}
