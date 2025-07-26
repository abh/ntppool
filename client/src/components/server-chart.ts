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

      // Create the D3 chart with explicit dimensions
      createServerChart(this.chartContainer, this.data as ServerScoreHistoryResponse, {
        legend: legendElement,
        showTooltips: true,
        responsive: true,
        width: this.options.width,
        height: this.options.height,
        showOnlyActiveTesting: this.shouldShowLegendOnly()
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
}

// Register the custom element
if (!customElements.get('ntp-server-chart')) {
  customElements.define('ntp-server-chart', ServerChartComponent);
}

// Export for external registration
export { ServerChartComponent as default };
