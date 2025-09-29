import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "content", "originalXml", "updatedXml", "loading"]
  static values = {
    previewUrl: String,
    applyUrl: String
  }

  connect() {
    // Bind the escape key to close modal
    this.boundHandleEscape = this.handleEscape.bind(this)
  }

  disconnect() {
    document.removeEventListener('keydown', this.boundHandleEscape)
  }

  async showDiff() {
    this.showModal()
    this.showLoading()

    try {
      const response = await fetch(this.previewUrlValue, {
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })

      if (!response.ok) {
        const errorText = await response.text()
        console.error('Response error:', errorText)
        throw new Error(`HTTP ${response.status}: ${response.statusText}`)
      }

      const data = await response.json()
      this.displayDiff(data)
    } catch (error) {
      console.error('Error fetching diff:', error)
      this.showError(`Failed to load diff preview: ${error.message}`)
    }
  }

  showModal() {
    this.modalTarget.classList.remove('hidden')
    document.body.classList.add('overflow-hidden')
    document.addEventListener('keydown', this.boundHandleEscape)
  }

  hideModal() {
    this.modalTarget.classList.add('hidden')
    document.body.classList.remove('overflow-hidden')
    document.removeEventListener('keydown', this.boundHandleEscape)
  }

  showLoading() {
    this.loadingTarget.classList.remove('hidden')
    this.contentTarget.classList.add('hidden')
  }

  hideLoading() {
    this.loadingTarget.classList.add('hidden')
    this.contentTarget.classList.remove('hidden')
  }

  displayDiff(data) {
    this.hideLoading()

    if (!data.has_changes) {
      this.showNoChanges()
      return
    }

    // Production diff display
    this.contentTarget.innerHTML = `
      <div class="px-6 pt-6 pb-4">
        <div class="flex items-center mb-4">
          <div class="flex-shrink-0 flex items-center justify-center h-10 w-10 rounded-full bg-blue-100">
            <svg class="h-6 w-6 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
            </svg>
          </div>
          <div class="ml-4">
            <h3 class="text-lg font-medium text-white">Template Changes Preview</h3>
            <p class="text-sm text-gray-400">Review the changes that will be made to your local template file</p>
          </div>
        </div>

        <div class="mb-6">
          <h4 class="text-sm font-medium text-gray-300 mb-3">Changes to Apply:</h4>
          <div class="bg-gray-900 rounded-lg p-4 border border-gray-600 diff-container" style="max-height: 500px; overflow-y: auto; min-height: 200px;">
            ${this.cleanupDiffHtml(data.diff_html) || 'No changes detected'}
          </div>
          <p class="text-xs text-gray-400 mt-2">
            <span class="text-red-400">■ Red lines</span> will be removed •
            <span class="text-green-400">■ Green lines</span> will be added
          </p>
        </div>
      </div>

      <div class="bg-gray-700 px-6 py-4 flex justify-end gap-3">
        <button type="button"
                data-action="click->diff-modal#hideModal"
                class="px-4 py-2 border border-gray-600 rounded-md text-sm font-medium text-gray-300 hover:bg-gray-600 focus:outline-none focus:ring-2 focus:ring-blue-500 cursor-pointer">
          Cancel
        </button>
        <button type="button"
                data-action="click->diff-modal#confirmApply"
                class="px-4 py-2 bg-red-600 border border-transparent rounded-md text-sm font-medium text-white hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500 cursor-pointer">
          Apply Changes
        </button>
      </div>
    `
  }

  showNoChanges() {
    this.hideLoading()

    this.contentTarget.innerHTML = `
      <div class="px-6 pt-6 pb-4">
        <div class="text-center py-12">
          <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <h3 class="mt-2 text-sm font-medium text-white">No Changes Detected</h3>
          <p class="mt-1 text-sm text-gray-400">The template content will remain the same with your current choices.</p>
        </div>
      </div>

      <div class="bg-gray-700 px-6 py-4 flex justify-end">
        <button type="button"
                data-action="click->diff-modal#hideModal"
                class="px-4 py-2 border border-gray-600 rounded-md text-sm font-medium text-gray-300 hover:bg-gray-600 focus:outline-none focus:ring-2 focus:ring-blue-500 cursor-pointer">
          Close
        </button>
      </div>
    `
  }

  displayDiffInOriginalTargets(data) {
    if (!data.has_changes) {
      // Replace the grid with no changes message
      const gridContainer = this.contentTarget.querySelector('.grid')
      if (gridContainer) {
        gridContainer.innerHTML = `
          <div class="col-span-2 text-center py-12">
            <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <h3 class="mt-2 text-sm font-medium text-white">No Changes Detected</h3>
            <p class="mt-1 text-sm text-gray-400">The template content will remain the same with your current choices.</p>
          </div>
        `
      }
      return
    }

    // Display content in original targets
    if (this.originalXmlTarget) {
      this.originalXmlTarget.textContent = data.original || 'No content available'
    }
    if (this.updatedXmlTarget) {
      this.updatedXmlTarget.textContent = data.updated || 'No content available'
    }

    console.log('Content set in original targets')
  }

  displayDiffInNewStructure(data) {
    // Fallback to completely replacing content
    this.contentTarget.innerHTML = `
      <div class="px-4 pt-5 pb-4 sm:p-6 sm:pb-4">
        <div class="sm:flex sm:items-start">
          <div class="mx-auto flex-shrink-0 flex items-center justify-center h-12 w-12 rounded-full bg-blue-100 sm:mx-0 sm:h-10 sm:w-10">
            <svg class="h-6 w-6 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
            </svg>
          </div>
          <div class="mt-3 text-center sm:mt-0 sm:ml-4 sm:text-left flex-1">
            <h3 class="text-lg leading-6 font-medium text-white">Template Changes Preview</h3>
            <div class="mt-4">
              ${this.renderDiffContent(data)}
            </div>
          </div>
        </div>
      </div>
      <div class="bg-gray-700 px-4 py-3 sm:px-6 sm:flex sm:flex-row-reverse">
        <button type="button"
                data-action="click->diff-modal#confirmApply"
                class="w-full inline-flex justify-center rounded-md border border-transparent shadow-sm px-4 py-2 bg-red-600 text-base font-medium text-white hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500 sm:ml-3 sm:w-auto sm:text-sm cursor-pointer">
          Apply Changes
        </button>
        <button type="button"
                data-action="click->diff-modal#hideModal"
                class="mt-3 w-full inline-flex justify-center rounded-md border border-gray-600 shadow-sm px-4 py-2 bg-gray-700 text-base font-medium text-gray-300 hover:bg-gray-600 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 sm:mt-0 sm:ml-3 sm:w-auto sm:text-sm cursor-pointer">
          Cancel
        </button>
      </div>
    `
  }

  renderDiffContent(data) {
    if (!data.has_changes) {
      return `
        <div class="text-center py-12">
          <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <h3 class="mt-2 text-sm font-medium text-white">No Changes Detected</h3>
          <p class="mt-1 text-sm text-gray-400">The template content will remain the same with your current choices.</p>
        </div>
      `
    }

    if (data.diff_html && data.diff_html.trim() !== '<div class="diff"></div>') {
      return `
        <div class="mb-4">
          <h4 class="text-sm font-medium text-gray-300 mb-2 flex items-center">
            <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
            </svg>
            Template Changes
          </h4>
          <div class="bg-gray-900 border border-gray-600 rounded p-3 max-h-96 overflow-y-auto diff-container">
            ${data.diff_html}
          </div>
          <p class="text-xs text-gray-400 mt-2">
            <span class="text-red-400">Red lines</span> will be removed,
            <span class="text-green-400">green lines</span> will be added
          </p>
        </div>
      `
    }

    // Fallback to side-by-side view
    return `
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <h4 class="text-sm font-medium text-gray-300 mb-2 flex items-center">
            <span class="w-3 h-3 bg-red-500 rounded-full mr-2"></span>
            Current (Local)
          </h4>
          <div class="bg-gray-900 border border-gray-600 rounded p-3 max-h-96 overflow-y-auto">
            <pre class="text-xs text-gray-300 whitespace-pre-wrap">${this.escapeHtml(data.original || 'No content')}</pre>
          </div>
        </div>
        <div>
          <h4 class="text-sm font-medium text-gray-300 mb-2 flex items-center">
            <span class="w-3 h-3 bg-green-500 rounded-full mr-2"></span>
            After Changes
          </h4>
          <div class="bg-gray-900 border border-gray-600 rounded p-3 max-h-96 overflow-y-auto">
            <pre class="text-xs text-gray-300 whitespace-pre-wrap">${this.escapeHtml(data.updated || 'No content')}</pre>
          </div>
        </div>
      </div>
    `
  }

  showUnifiedDiff(diffHtml) {
    console.log('showUnifiedDiff called with HTML length:', diffHtml.length)
    // Replace the two-column layout with a single unified diff
    const diffContainer = this.contentTarget.querySelector('.grid')
    console.log('Found diff container:', diffContainer)
    if (!diffContainer) {
      console.error('Could not find .grid container')
      return
    }
    diffContainer.innerHTML = `
      <div class="col-span-2">
        <h4 class="text-sm font-medium text-gray-300 mb-2 flex items-center">
          <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
          </svg>
          Template Changes
        </h4>
        <div class="bg-gray-900 border border-gray-600 rounded p-3 max-h-96 overflow-y-auto diff-container">
          ${diffHtml}
        </div>
        <p class="text-xs text-gray-400 mt-2">
          <span class="text-red-400">Red lines</span> will be removed,
          <span class="text-green-400">green lines</span> will be added
        </p>
      </div>
    `
  }

  showSideBySideDiff(original, updated) {
    // Fallback to side-by-side view
    this.originalXmlTarget.innerHTML = `<code class="text-xs">${this.escapeHtml(original)}</code>`
    this.updatedXmlTarget.innerHTML = `<code class="text-xs">${this.escapeHtml(updated)}</code>`
  }

  showNoChanges() {
    console.log('showNoChanges called')
    const diffContainer = this.contentTarget.querySelector('.grid')
    console.log('Found diff container for no changes:', diffContainer)
    if (!diffContainer) {
      console.error('Could not find .grid container in showNoChanges')
      // Fallback: set content directly on contentTarget
      this.contentTarget.innerHTML = `
        <div class="px-4 pt-5 pb-4 sm:p-6 sm:pb-4">
          <div class="text-center py-12">
            <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <h3 class="mt-2 text-sm font-medium text-white">No Changes Detected</h3>
            <p class="mt-1 text-sm text-gray-400">The template content will remain the same with your current choices.</p>
          </div>
        </div>
      `
      return
    }
    diffContainer.innerHTML = `
      <div class="col-span-2 text-center py-12">
        <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
        <h3 class="mt-2 text-sm font-medium text-white">No Changes Detected</h3>
        <p class="mt-1 text-sm text-gray-400">The template content will remain the same with your current choices.</p>
      </div>
    `
    console.log('No changes content set')
  }

  formatXml(xmlString) {
    // Basic XML formatting - could be enhanced with a proper formatter
    return xmlString
      .replace(/></g, '>\n<')
      .replace(/^\s*\n/gm, '')
  }

  highlightDifferences() {
    // This is a basic implementation - could be enhanced with a proper diff library
    const originalLines = this.originalXmlTarget.textContent.split('\n')
    const updatedLines = this.updatedXmlTarget.textContent.split('\n')

    // For now, just wrap the content in a code block
    this.originalXmlTarget.innerHTML = `<code class="text-sm">${this.escapeHtml(this.originalXmlTarget.textContent)}</code>`
    this.updatedXmlTarget.innerHTML = `<code class="text-sm">${this.escapeHtml(this.updatedXmlTarget.textContent)}</code>`
  }

  cleanupDiffHtml(html) {
    if (!html) return html

    // Create a temporary container to manipulate the HTML
    const tempDiv = document.createElement('div')
    tempDiv.innerHTML = html

    // Find all UL elements and remove whitespace text nodes between LI elements
    const uls = tempDiv.querySelectorAll('ul')
    uls.forEach(ul => {
      // Get all child nodes (including text nodes)
      const childNodes = Array.from(ul.childNodes)

      childNodes.forEach(node => {
        // Remove whitespace-only text nodes
        if (node.nodeType === Node.TEXT_NODE && node.textContent.trim() === '') {
          node.remove()
        }
      })
    })

    return tempDiv.innerHTML
  }

  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }

  showError(message) {
    this.hideLoading()
    this.contentTarget.innerHTML = `
      <div class="text-center py-12">
        <div class="text-red-400 text-lg mb-4">Error</div>
        <p class="text-gray-300">${message}</p>
      </div>
    `
    this.contentTarget.classList.remove('hidden')
  }

  async confirmApply() {
    // Create a form and submit it to apply the changes
    const form = document.createElement('form')
    form.method = 'POST'
    form.action = this.applyUrlValue

    // Add CSRF token
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    if (csrfToken) {
      const csrfInput = document.createElement('input')
      csrfInput.type = 'hidden'
      csrfInput.name = 'authenticity_token'
      csrfInput.value = csrfToken
      form.appendChild(csrfInput)
    }

    // Add method override for PATCH
    const methodInput = document.createElement('input')
    methodInput.type = 'hidden'
    methodInput.name = '_method'
    methodInput.value = 'patch'
    form.appendChild(methodInput)

    document.body.appendChild(form)
    form.submit()
  }

  handleEscape(event) {
    if (event.key === 'Escape') {
      this.hideModal()
    }
  }

  // Action to handle backdrop clicks
  handleBackdropClick(event) {
    if (event.target === this.modalTarget) {
      this.hideModal()
    }
  }
}
