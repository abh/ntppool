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
    return [...super.observedAttributes, 'server-ip', 'show-legend'];
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
      console.log('🎯 Web Component Render Debug v2.1:', {
        serverIp: this.getServerIp(),
        options: this.options,
        chartContainer: this.chartContainer,
        containerDimensions: {
          offsetWidth: this.chartContainer.offsetWidth,
          offsetHeight: this.chartContainer.offsetHeight,
          clientWidth: this.chartContainer.clientWidth,
          clientHeight: this.chartContainer.clientHeight
        },
        webComponentAttributes: {
          width: this.getAttribute('width'),
          height: this.getAttribute('height'),
          serverIp: this.getAttribute('server-ip'),
          showLegend: this.getAttribute('show-legend')
        }
      });

      // Get legend element for the chart function
      const legendElement = this.shouldShowLegend() && this.legendContainer ? this.legendContainer : null;

      // Create the D3 chart with explicit dimensions
      createServerChart(this.chartContainer, this.data as ServerScoreHistoryResponse, {
        legend: legendElement,
        showTooltips: true,
        responsive: true,
        width: this.options.width,
        height: this.options.height
      });

      // Update container dimensions
      this.updateContainerDimensions();

    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to render chart';
      console.error('❌ Server Chart Render Error:', error);
      this.showErrorState(message);
    }
  }

  protected getComponentStyles(): string {
    const baseStyles = `
      /* Server chart specific styles */
      .chart-container {
        background: white;
        border-radius: 4px;
        box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
      }

      .legend-container {
        margin-top: 1rem;
        padding: 0.75rem;
        background: #f9fafb;
        border-radius: 4px;
        border: 1px solid #e5e7eb;
      }

      .legend-container table {
        width: 100%;
        font-size: 0.875rem;
      }

      .legend-container th,
      .legend-container td {
        padding: 0.25rem 0.5rem;
        text-align: left;
      }

      .legend-container tr:hover {
        background-color: rgba(59, 130, 246, 0.05);
      }

      /* SVG chart styling */
      .chart-container svg {
        width: 100%;
        height: auto;
        max-width: 100%;
      }

      /* Responsive adjustments */
      @container (max-width: 600px) {
        .legend-container {
          margin-top: 0.5rem;
          padding: 0.5rem;
        }

        .legend-container table {
          font-size: 0.75rem;
        }
      }
    `;

    const fallbackStyles = this.useShadowDOM && !this.shouldInheritStyles() ? `
      /* Fallback styles when using shadow DOM without inheritance */
      .legend-container table {
        border-collapse: collapse;
      }

      .legend-container th,
      .legend-container td {
        border-bottom: 1px solid #e5e7eb;
      }

      .legend-container .table-success {
        background-color: rgba(16, 185, 129, 0.1);
      }

      .legend-container .table-info {
        background-color: rgba(59, 130, 246, 0.1);
      }

      .legend-container .table-secondary {
        background-color: rgba(107, 114, 128, 0.1);
      }

      .legend-container .table-danger {
        background-color: rgba(239, 68, 68, 0.1);
      }

      .legend-container .fw-bold {
        font-weight: 600;
      }
    ` : '';

    return baseStyles + fallbackStyles;
  }

  // Private helper methods

  private createLegendContainer(): void {
    if (this.legendContainer) return;

    this.legendContainer = document.createElement('div');
    this.legendContainer.className = 'legend-container';

    if (this.useShadowDOM && this.shadow) {
      this.shadow.appendChild(this.legendContainer);
    } else {
      this.appendChild(this.legendContainer);
    }
  }

  private removeLegendContainer(): void {
    if (this.legendContainer) {
      if (this.useShadowDOM && this.shadow) {
        this.shadow.removeChild(this.legendContainer);
      } else {
        this.removeChild(this.legendContainer);
      }
      delete this.legendContainer;
    }
  }

  private updateContainerDimensions(): void {
    const svg = this.chartContainer.querySelector('svg');
    if (svg) {
      // Calculate total dimensions from chart content + padding
      const totalWidth = this.options.width + (45 * 2);   // Chart width + horizontal padding
      const totalHeight = this.options.height + (19 * 2); // Chart height + vertical padding

      console.log('🖼️ Web Component SVG Update Debug:', {
        options: this.options,
        totalWidth,
        totalHeight,
        currentSvgAttributes: {
          width: svg.getAttribute('width'),
          height: svg.getAttribute('height'),
          viewBox: svg.getAttribute('viewBox'),
          styleWidth: svg.style.width,
          styleHeight: svg.style.height
        },
        containerDimensions: {
          offsetWidth: this.chartContainer.offsetWidth,
          offsetHeight: this.chartContainer.offsetHeight
        },
        webComponentDimensions: {
          offsetWidth: this.offsetWidth,
          offsetHeight: this.offsetHeight,
          clientWidth: this.clientWidth,
          clientHeight: this.clientHeight,
          scrollWidth: this.scrollWidth,
          scrollHeight: this.scrollHeight
        },
        computedStyles: {
          webComponent: window.getComputedStyle(this),
          chartContainer: window.getComputedStyle(this.chartContainer)
        }
      });

      // Set specific dimensions to avoid scaling issues
      svg.setAttribute('width', totalWidth.toString());
      svg.setAttribute('height', totalHeight.toString());
      svg.setAttribute('viewBox', `0 0 ${totalWidth} ${totalHeight}`);
      svg.setAttribute('preserveAspectRatio', 'xMidYMid meet');

      // Set CSS dimensions to match exactly
      svg.style.width = `${totalWidth}px`;
      svg.style.height = `${totalHeight}px`;

      console.log('🖼️ After SVG Update:', {
        finalSvgAttributes: {
          width: svg.getAttribute('width'),
          height: svg.getAttribute('height'),
          viewBox: svg.getAttribute('viewBox'),
          styleWidth: svg.style.width,
          styleHeight: svg.style.height
        }
      });
    }
  }
}

// Register the custom element
if (!customElements.get('ntp-server-chart')) {
  customElements.define('ntp-server-chart', ServerChartComponent);
}

// Export for external registration
export { ServerChartComponent as default };
