/**
 * Server Chart Web Component
 * Displays NTP server offset and score history
 */

import { BaseChartComponent } from './base-chart.js';
import { createServerChart } from '@/charts/server-chart.js';
import type { ServerScoreHistoryResponse } from '@/types/index.js';

/**
 * Server Chart Component
 * Usage: <ntp-server-chart server-ip="192.168.1.100" show-legend="true"></ntp-server-chart>
 */
export class ServerChartComponent extends BaseChartComponent {
  private legendContainer?: HTMLDivElement;
  private developerMenu?: HTMLDivElement;
  private isDeveloperMode = false;

  static override get observedAttributes(): string[] {
    return [...super.observedAttributes, 'server-ip', 'show-legend', 'show-legend-only'];
  }

  constructor() {
    super();
    // Dimensions set by HTML attributes, no overrides needed
  }

  override connectedCallback(): void {
    // Validate required attributes
    if (!this.validateAttributes()) {
      this.showErrorState('Missing required server-ip attribute');
      return;
    }

    // Create legend container if requested
    if (this.shouldShowLegend()) {
      this.createLegendContainer();
    }

    super.connectedCallback();

    // Set up developer mode keypress handler
    this.setupDeveloperMode();
  }

  override attributeChangedCallback(name: string, oldValue: string | null, newValue: string | null): void {
    super.attributeChangedCallback(name, oldValue, newValue);

    // Reload chart if server IP changes
    if (name === 'server-ip' && oldValue !== newValue && newValue) {
      if (this.validateAttributes()) {
        this.loadChart();
      } else {
        this.showErrorState('Invalid server-ip attribute');
      }
    }

    // Handle legend visibility changes
    if (name === 'show-legend' && oldValue !== newValue) {
      if (this.shouldShowLegend() && !this.legendContainer) {
        this.createLegendContainer();
      } else if (!this.shouldShowLegend() && this.legendContainer) {
        this.removeLegendContainer();
      }

      // Re-render if we have data
      if (this.data) {
        this.render();
      }
    }

    // Handle legend filter changes
    if (name === 'show-legend-only' && oldValue !== newValue) {
      // Re-render if we have data and legend is visible
      if (this.data && this.shouldShowLegend()) {
        this.render();
      }
    }
  }

  /**
   * Get the server IP from attributes
   */
  getServerIp(): string | null {
    return this.getAttribute('server-ip');
  }

  /**
   * Check if legend should be shown
   */
  shouldShowLegend(): boolean {
    return this.getAttribute('show-legend') === 'true';
  }

  /**
   * Set server IP and reload chart
   */
  setServerIp(serverIp: string): void {
    this.setAttribute('server-ip', serverIp);
  }

  /**
   * Toggle legend visibility
   */
  setShowLegend(show: boolean): void {
    this.setAttribute('show-legend', show.toString());
  }

  /**
   * Check if legend should show only active and testing monitors
   */
  shouldShowLegendOnly(): boolean {
    return this.getAttribute('show-legend-only') === 'true';
  }

  /**
   * Toggle legend filter to show only active and testing monitors
   */
  setShowLegendOnly(show: boolean): void {
    this.setAttribute('show-legend-only', show.toString());
  }

  // Protected methods (implementation of abstract methods)

  protected getDataUrl(): string {
    const serverIp = this.getServerIp();
    if (!serverIp) {
      throw new Error('Server IP is required');
    }
    const devSettings = this.getDeveloperSettings();
    return `/scores/${serverIp}/json?monitor=*&limit=${devSettings.dataPoints}&source=c`;
  }

  protected validateAttributes(): boolean {
    const serverIp = this.getServerIp();
    if (!serverIp) return false;

    // Basic IP validation (IPv4 or IPv6)
    const ipv4Regex = /^(\d{1,3}\.){3}\d{1,3}$/;
    const ipv6Regex = /^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$/;

    return ipv4Regex.test(serverIp) || ipv6Regex.test(serverIp) || serverIp.includes(':');
  }

  protected render(): void {
    if (!this.data) return;

    this.clearChart();

    try {

      // Get legend element for the chart function
      const legendElement = this.shouldShowLegend() && this.legendContainer ? this.legendContainer : null;

      // Create the D3 chart with explicit dimensions
      createServerChart(this.chartContainer, this.data as ServerScoreHistoryResponse, {
        legend: legendElement,
        showTooltips: true,
        responsive: true,
        width: this.options.width,
        height: this.options.height,
        showOnlyActiveTesting: this.shouldShowLegendOnly(),
        developerMode: this.isDeveloperMode
      });

      // Update container dimensions
      this.updateContainerDimensions();

    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to render chart';
      console.error('❌ Server Chart Render Error:', error);
      this.showErrorState(message);
    }
  }


  // Private helper methods

  private createLegendContainer(): void {
    if (this.legendContainer) return;

    this.legendContainer = document.createElement('div');
    this.legendContainer.className = 'legend-container';

    // Always use direct DOM attachment (inherit-styles="true" in all templates)
    this.appendChild(this.legendContainer);
  }

  private removeLegendContainer(): void {
    if (this.legendContainer) {
      this.removeChild(this.legendContainer);
      delete this.legendContainer;
    }
  }

  private updateContainerDimensions(): void {
    const svg = this.chartContainer.querySelector('svg');
    if (svg) {
      // Calculate total dimensions from chart content + padding
      const totalWidth = this.options.width + (45 * 2);   // Chart width + horizontal padding
      const totalHeight = this.options.height + (19 * 2); // Chart height + vertical padding


      // Set specific dimensions to avoid scaling issues
      svg.setAttribute('width', totalWidth.toString());
      svg.setAttribute('height', totalHeight.toString());
      svg.setAttribute('viewBox', `0 0 ${totalWidth} ${totalHeight}`);
      svg.setAttribute('preserveAspectRatio', 'xMidYMid meet');

      // Set CSS dimensions to match exactly
      svg.setAttribute('width', totalWidth.toString());
      svg.setAttribute('height', totalHeight.toString());

    }
  }

  /**
   * Set up developer mode functionality
   */
  private setupDeveloperMode(): void {
    // Add keypress listener to document for global access
    document.addEventListener('keydown', (event) => {
      // Ctrl+Shift+D to toggle developer mode
      if (event.ctrlKey && event.shiftKey && event.key === 'D') {
        event.preventDefault();
        this.toggleDeveloperMode();
      }
    });
  }

  /**
   * Toggle developer mode on/off
   */
  private toggleDeveloperMode(): void {
    this.isDeveloperMode = !this.isDeveloperMode;

    if (this.isDeveloperMode) {
      this.createDeveloperMenu();
    } else {
      this.removeDeveloperMenu();
    }
  }

  /**
   * Create developer menu UI
   */
  private createDeveloperMenu(): void {
    if (this.developerMenu) return;

    this.developerMenu = document.createElement('div');
    this.developerMenu.className = 'developer-menu';
    this.developerMenu.innerHTML = `
      <div class="card border-warning">
        <div class="card-header bg-warning text-dark">
          <small><strong>🔧 Developer Mode</strong> (Ctrl+Shift+D to toggle)</small>
        </div>
        <div class="card-body">
          <p class="text-muted small mb-2">Chart configuration options</p>
          <div class="mb-2">
            <label class="form-label small" for="dataPointsSelect">Data Points:</label>
            <select class="form-select form-select-sm" id="dataPointsSelect">
              <option value="1000">1,000</option>
              <option value="3000">3,000</option>
              <option value="6500" selected>6,500 (default)</option>
              <option value="9000">9,000</option>
              <option value="12000">12,000</option>
              <option value="20000">20,000</option>
              <option value="30000">30,000</option>
              <option value="50000">50,000</option>
            </select>
          </div>
        </div>
      </div>
    `;

    // Append after chart container
    this.appendChild(this.developerMenu);

    // Set up event listeners
    this.setupDeveloperMenuEvents();

    // Load saved preferences
    this.loadDeveloperPreferences();
  }

  /**
   * Set up developer menu event listeners
   */
  private setupDeveloperMenuEvents(): void {
    if (!this.developerMenu) return;

    const dataPointsSelect = this.developerMenu.querySelector('#dataPointsSelect') as HTMLSelectElement;

    if (dataPointsSelect) {
      dataPointsSelect.addEventListener('change', () => {
        this.updateDeveloperSettings();
      });
    }
  }

  /**
   * Update developer settings and re-render chart
   */
  private updateDeveloperSettings(): void {
    if (!this.developerMenu) return;

    const dataPointsSelect = this.developerMenu.querySelector('#dataPointsSelect') as HTMLSelectElement;

    // Store settings in localStorage for persistence
    const newDataPoints = dataPointsSelect?.value || '6500';

    localStorage.setItem('ntppool-dev-ex1-dataPoints', newDataPoints);

    // Clean up invalid ntppool-dev- entries (keep only valid experiments)
    this.cleanupInvalidDevSettings();

    // Refresh chart data with new limit
    this.refresh();
  }

  /**
   * Remove developer menu
   */
  private removeDeveloperMenu(): void {
    if (this.developerMenu) {
      this.removeChild(this.developerMenu);
      delete this.developerMenu;
    }
  }

  /**
   * Load saved developer preferences into the menu
   */
  private loadDeveloperPreferences(): void {
    if (!this.developerMenu) return;

    const settings = this.getDeveloperSettings();

    const dataPointsSelect = this.developerMenu.querySelector('#dataPointsSelect') as HTMLSelectElement;

    if (dataPointsSelect) {
      dataPointsSelect.value = settings.dataPoints.toString();
    }
  }

  /**
   * Get current developer settings
   */
  private getDeveloperSettings() {
    return {
      dataPoints: parseInt(localStorage.getItem('ntppool-dev-ex1-dataPoints') || '6500', 10)
    };
  }

  /**
   * Clean up invalid ntppool-dev- localStorage entries
   * Only keeps entries with valid experiment prefixes (currently only 'ex1')
   */
  private cleanupInvalidDevSettings(): void {
    const validExperiments = ['ex1'];
    const keysToRemove: string[] = [];

    // Check all localStorage keys
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      if (key && key.startsWith('ntppool-dev-')) {
        // Check if it's a valid experiment key
        const isValid = validExperiments.some(exp =>
          key.startsWith(`ntppool-dev-${exp}-`)
        );

        if (!isValid) {
          keysToRemove.push(key);
        }
      }
    }

    // Remove invalid keys
    keysToRemove.forEach(key => {
      localStorage.removeItem(key);
    });
  }
}

// Register the custom element
if (!customElements.get('ntp-server-chart')) {
  customElements.define('ntp-server-chart', ServerChartComponent);
}

// Export for external registration
export { ServerChartComponent as default };
