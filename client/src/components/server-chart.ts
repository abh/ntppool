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
    return `/scores/${serverIp}/json?monitor=*&limit=6500&source=c`;
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

      // Get developer settings
      const devSettings = this.getDeveloperSettings();


      // Create the D3 chart with explicit dimensions
      createServerChart(this.chartContainer, this.data as ServerScoreHistoryResponse, {
        legend: legendElement,
        showTooltips: true,
        responsive: true,
        width: this.options.width,
        height: this.options.height,
        showOnlyActiveTesting: this.shouldShowLegendOnly(),
        developerMode: this.isDeveloperMode,
        dateFormat: devSettings.dateFormat,
        compactHours: devSettings.compactHours,
        showYearOnFirstTick: devSettings.showYear
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
          <div class="row">
            <div class="col-md-6">
              <div class="form-group mb-2">
                <label class="form-label small">Date Format:</label>
                <select class="form-select form-select-sm" id="dateFormatSelect">
                  <option value="default">Default (%H:%M / %b %d %H:%M)</option>
                  <option value="iso">ISO Format (%Y-%m-%dT%H:%M)</option>
                  <option value="year-first">Year First (%Y-%m-%d %H:%M)</option>
                  <option value="verbose">Verbose (%A, %B %d, %Y %H:%M)</option>
                  <option value="compact">Compact (%m/%d %H:%M)</option>
                </select>
              </div>
            </div>
            <div class="col-md-6">
              <div class="form-check mb-2">
                <input class="form-check-input" type="checkbox" id="compactHoursCheck">
                <label class="form-check-label small" for="compactHoursCheck">
                  Compact hours (6h vs 06:00)
                </label>
              </div>
              <div class="form-check mb-2">
                <input class="form-check-input" type="checkbox" id="showYearCheck">
                <label class="form-check-label small" for="showYearCheck">
                  Show year on first tick
                </label>
              </div>
            </div>
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

    const dateFormatSelect = this.developerMenu.querySelector('#dateFormatSelect') as HTMLSelectElement;
    const compactHoursCheck = this.developerMenu.querySelector('#compactHoursCheck') as HTMLInputElement;
    const showYearCheck = this.developerMenu.querySelector('#showYearCheck') as HTMLInputElement;

    if (dateFormatSelect) {
      dateFormatSelect.addEventListener('change', () => {
        this.updateDeveloperSettings();
      });
    }

    if (compactHoursCheck) {
      compactHoursCheck.addEventListener('change', () => {
        this.updateDeveloperSettings();
      });
    }

    if (showYearCheck) {
      showYearCheck.addEventListener('change', () => {
        this.updateDeveloperSettings();
      });
    }
  }

  /**
   * Update developer settings and re-render chart
   */
  private updateDeveloperSettings(): void {
    if (!this.developerMenu) return;

    const dateFormatSelect = this.developerMenu.querySelector('#dateFormatSelect') as HTMLSelectElement;
    const compactHoursCheck = this.developerMenu.querySelector('#compactHoursCheck') as HTMLInputElement;
    const showYearCheck = this.developerMenu.querySelector('#showYearCheck') as HTMLInputElement;

    // Store settings in localStorage for persistence
    const newDateFormat = dateFormatSelect?.value || 'default';
    const newCompactHours = compactHoursCheck?.checked ? 'true' : 'false';
    const newShowYear = showYearCheck?.checked ? 'true' : 'false';

    localStorage.setItem('ntppool-dev-dateFormat', newDateFormat);
    localStorage.setItem('ntppool-dev-compactHours', newCompactHours);
    localStorage.setItem('ntppool-dev-showYear', newShowYear);

    // Re-render chart with new settings
    this.render();
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

    const dateFormatSelect = this.developerMenu.querySelector('#dateFormatSelect') as HTMLSelectElement;
    const compactHoursCheck = this.developerMenu.querySelector('#compactHoursCheck') as HTMLInputElement;
    const showYearCheck = this.developerMenu.querySelector('#showYearCheck') as HTMLInputElement;

    if (dateFormatSelect) {
      dateFormatSelect.value = settings.dateFormat;
    }
    if (compactHoursCheck) {
      compactHoursCheck.checked = settings.compactHours;
    }
    if (showYearCheck) {
      showYearCheck.checked = settings.showYear;
    }
  }

  /**
   * Get current developer settings
   */
  private getDeveloperSettings() {
    return {
      dateFormat: localStorage.getItem('ntppool-dev-dateFormat') || 'default',
      compactHours: localStorage.getItem('ntppool-dev-compactHours') === 'true',
      showYear: localStorage.getItem('ntppool-dev-showYear') === 'true'
    };
  }
}

// Register the custom element
if (!customElements.get('ntp-server-chart')) {
  customElements.define('ntp-server-chart', ServerChartComponent);
}

// Export for external registration
export { ServerChartComponent as default };
