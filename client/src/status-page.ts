/**
 * Status Page Integration
 * Fetches status from status.ntppool.org API and updates footer indicator
 */

interface StatusPageResponse {
  page: {
    id: string;
    name: string;
    url: string;
  };
  status: {
    indicator: 'none' | 'minor' | 'major' | 'critical';
    description: string;
  };
}

/**
 * Fetches status data from the StatusPage API
 */
async function fetchStatusPageData(): Promise<StatusPageResponse | null> {
  try {
    const response = await fetch('/api/status/v2/summary.json');

    if (!response.ok) {
      console.warn(`Status API returned ${response.status}: ${response.statusText}`);
      return null;
    }

    const data: StatusPageResponse = await response.json();
    return data;
  } catch (error) {
    console.warn('Failed to fetch status page data:', error);
    return null;
  }
}

/**
 * Updates the status indicator elements in the DOM
 */
function updateStatusIndicator(statusData: StatusPageResponse): void {
  const colorDot = document.querySelector('.color-dot');
  const colorDescription = document.querySelector('.color-description');

  if (!colorDot || !colorDescription) {
    console.warn('Status indicator elements not found in DOM');
    return;
  }

  // Update status text
  colorDescription.textContent = statusData.status.description;

  // Remove existing status classes and add the current one
  colorDot.classList.remove('none', 'minor', 'major', 'critical');
  colorDot.classList.add(statusData.status.indicator);
}

/**
 * Hides the status indicator elements
 */
function hideStatusIndicator(): void {
  const statusLink = document.querySelector('a[href="https://status.ntppool.org/"]') as HTMLElement;
  if (statusLink) {
    statusLink.style.display = 'none';
  }
}

/**
 * Initializes the status page integration
 */
export async function initializeStatusPage(): Promise<void> {
  try {
    const statusData = await fetchStatusPageData();

    if (statusData) {
      updateStatusIndicator(statusData);
    } else {
      hideStatusIndicator();
    }
  } catch (error) {
    console.error('Failed to initialize status page:', error);
    hideStatusIndicator();
  }
}
