import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    url: String,
    interval: { type: Number, default: 5000 },
    enabled: { type: Boolean, default: true }
  }

  connect() {
    if (this.enabledValue) {
      this.startRefreshing()
    }
  }

  disconnect() {
    this.stopRefreshing()
  }

  startRefreshing() {
    this.stopRefreshing() // Clear any existing interval

    this.refreshInterval = setInterval(() => {
      this.refresh()
    }, this.intervalValue)
  }

  stopRefreshing() {
    if (this.refreshInterval) {
      clearInterval(this.refreshInterval)
      this.refreshInterval = null
    }
  }

  async refresh() {
    try {
      // Use Turbo's built-in method for making requests
      const response = await fetch(this.urlValue.replace('.turbo_stream', ''), {
        headers: {
          'Accept': 'text/html',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })

      if (response.ok) {
        const html = await response.text()
        // Parse the HTML and update specific sections
        const parser = new DOMParser()
        const doc = parser.parseFromString(html, 'text/html')

        // Update running jobs section
        const runningJobsFrame = document.getElementById('running_jobs')
        const newRunningJobs = doc.getElementById('running_jobs')
        if (runningJobsFrame && newRunningJobs) {
          runningJobsFrame.innerHTML = newRunningJobs.innerHTML
        }

        // Update job history section
        const jobHistoryFrame = document.getElementById('job_history')
        const newJobHistory = doc.getElementById('job_history')
        if (jobHistoryFrame && newJobHistory) {
          jobHistoryFrame.innerHTML = newJobHistory.innerHTML
        }
      }
    } catch (error) {
      console.error('Auto-refresh failed:', error)
      // Don't stop refreshing on network errors, just log them
    }
  }

  // Allow manual refresh
  manualRefresh() {
    this.refresh()
  }

  // Toggle auto-refresh
  toggle() {
    if (this.refreshInterval) {
      this.stopRefreshing()
      this.enabledValue = false
    } else {
      this.startRefreshing()
      this.enabledValue = true
    }
  }
}
