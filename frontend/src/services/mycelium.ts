/**
 * Mycelium Detection and API Client
 *
 * Handles detection of local Mycelium installation and provides
 * interface to Mycelium P2P networking capabilities
 */

const MYCELIUM_API_BASE = '/api/mycelium';

export interface MyceliumStatus {
  detected: boolean;
  version?: string;
  peers?: number;
  connected: boolean;
  error?: string;
}

export interface MyceliumPeer {
  public_key: string;
  endpoint: string;
  state: string;
}

export interface MyceliumPeersResponse {
  peers: MyceliumPeer[];
}

export interface MyceliumAdminResponse {
  version: string;
  public_key: string;
  peers: MyceliumPeer[];
}

class MyceliumService {
  private baseUrl: string;

  constructor(baseUrl: string = MYCELIUM_API_BASE) {
    this.baseUrl = baseUrl;
  }

  /**
   * Detect if Mycelium is running locally
   */
  async detectMycelium(): Promise<MyceliumStatus> {
    try {
      console.log('🔍 Detecting Mycelium installation...');

      const response = await fetch(`${this.baseUrl}/api/v1/admin`, {
        method: 'GET',
        headers: {
          'Accept': 'application/json',
        },
        // Short timeout to avoid hanging
        signal: AbortSignal.timeout(2000),
      });

      if (response.ok) {
        const data: MyceliumAdminResponse = await response.json();
        console.log('✅ Mycelium detected:', data);

        return {
          detected: true,
          version: data.version,
          peers: data.peers?.length || 0,
          connected: true,
        };
      } else {
        console.log('⚠️ Mycelium responded but with error:', response.status);
        return {
          detected: false,
          connected: false,
          error: `HTTP ${response.status}`,
        };
      }
    } catch (error) {
      console.log('❌ Mycelium not detected:', error);
      return {
        detected: false,
        connected: false,
        error: error instanceof Error ? error.message : 'Unknown error',
      };
    }
  }

  /**
   * Get detailed peer information
   */
  async getPeers(): Promise<MyceliumPeersResponse | null> {
    try {
      const response = await fetch(`${this.baseUrl}/api/v1/peers`, {
        method: 'GET',
        headers: {
          'Accept': 'application/json',
        },
        signal: AbortSignal.timeout(3000),
      });

      if (response.ok) {
        return await response.json();
      }
    } catch (error) {
      console.error('Failed to get Mycelium peers:', error);
    }

    return null;
  }

  /**
   * Check if Mycelium has active P2P connections
   */
  async hasActiveConnections(): Promise<boolean> {
    const peers = await this.getPeers();
    return peers ? peers.peers.length > 0 : false;
  }

  /**
   * Get Mycelium network health status
   */
  async getNetworkHealth(): Promise<'excellent' | 'good' | 'fair' | 'poor' | 'offline'> {
    try {
      const status = await this.detectMycelium();
      if (!status.detected) return 'offline';

      const peers = await this.getPeers();
      const peerCount = peers?.peers.length || 0;

      if (peerCount >= 5) return 'excellent';
      if (peerCount >= 3) return 'good';
      if (peerCount >= 1) return 'fair';
      return 'poor';
    } catch {
      return 'offline';
    }
  }

  /**
   * Send a message through Mycelium P2P network
   * (Placeholder for future implementation)
   */
  async sendMessage(destination: string, message: any): Promise<boolean> {
    // TODO: Implement actual Mycelium message sending
    console.log('📤 Sending message via Mycelium:', { destination, message });
    return false; // Placeholder
  }

  /**
   * Receive messages from Mycelium P2P network
   * (Placeholder for future implementation)
   */
  async receiveMessages(): Promise<any[]> {
    // TODO: Implement actual Mycelium message receiving
    console.log('📥 Checking for Mycelium messages...');
    return []; // Placeholder
  }
}

// Export singleton instance
export const myceliumService = new MyceliumService();
export default myceliumService;