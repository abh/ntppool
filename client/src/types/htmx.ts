/**
 * HTMX-specific type definitions
 * Provides proper TypeScript types for HTMX events and configurations
 */

export interface HTMXEvent extends CustomEvent {
  target: HTMLElement;
  detail: {
    elt: HTMLElement;
    xhr: XMLHttpRequest;
    target?: HTMLElement;
    successful?: boolean;
    pathInfo?: {
      requestPath: string;
      verb: string;
    };
    requestConfig?: {
      url: string;
      verb: string;
      headers: Record<string, string>;
    };
  };
}

export interface AutoRedirectConfig {
  url: string;
  delay: number;
  message?: string;
}

export interface MonitorErrorConfig {
  errorDiv: string;
  messageSpan: string;
  traceidSpan: string;
}

export interface ErrorDetails {
  message: string;
  traceid: string;
}

export interface HTMXResponseError {
  error?: string;
  message?: string;
  traceid?: string;
}

// Global HTMX configuration interface
export interface HTMXConfig {
  includeIndicatorStyles: boolean;
  historyCacheSize: number;
  defaultSwapStyle?: string;
  refreshOnHistoryMiss?: boolean;
  indicatorClass?: string;
  requestClass?: string;
  addedClass?: string;
  settlingClass?: string;
  swappingClass?: string;
}

// HTMX instance interface
export interface HTMX {
  config: HTMXConfig;
  process: (element: Element) => void;
  find: (selector: string) => Element | null;
  findAll: (selector: string) => NodeListOf<Element>;
  trigger: (element: Element, eventName: string, detail?: any) => boolean;
}

// Extend global Window interface
declare global {
  interface Window {
    htmx: HTMX;
  }
}
