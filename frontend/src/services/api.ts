/**
 * API Client for Mycelium Matrix Chat Backend
 *
 * Handles all communication with the Web Gateway API endpoints
 */

const API_BASE_URL = 'http://localhost:8080';

// Response types
interface ApiResponse<T> {
  success: boolean;
  data: T | null;
  error: string | null;
}

interface CreateRoomRequest {
  room_name: string;
  topic?: string;
  is_public?: boolean;
}

interface CreateRoomResponse {
  room_id: string;
  room_name: string;
}

interface JoinRoomRequest {
  room_id: string;
}

interface JoinRoomResponse {
  room_id: string;
  joined: boolean;
}

interface RoomInfo {
  room_id: string;
  room_name: string;
  topic?: string;
  member_count: number;
}

interface ListRoomsResponse {
  rooms: RoomInfo[];
}

interface AuthRequest {
  username: string;
  password: string;
}

interface AuthResponse {
  access_token: string;
  user_id: string;
}

class ApiService {
  private baseUrl: string;

  constructor(baseUrl: string = API_BASE_URL) {
    this.baseUrl = baseUrl;
  }

  /**
   * Generic HTTP request helper
   */
  private async request<T>(
    endpoint: string,
    options: RequestInit = {}
  ): Promise<ApiResponse<T>> {
    try {
      const url = `${this.baseUrl}${endpoint}`;
      console.log(`🚀 API ${options.method || 'GET'} ${url}`, options.body);

      const response = await fetch(url, {
        headers: {
          'Content-Type': 'application/json',
          ...options.headers,
        },
        ...options,
      });

      const data = await response.json();
      console.log(`✅ API Response:`, data);

      if (!response.ok) {
        return {
          success: false,
          data: null,
          error: data.error || `HTTP ${response.status}: ${response.statusText}`,
        };
      }

      return {
        success: data.success !== false, // Default to true if not specified
        data: data.data || null,
        error: data.error || null,
      };
    } catch (error) {
      console.error(`❌ API Request failed:`, error);
      return {
        success: false,
        data: null,
        error: error instanceof Error ? error.message : 'Network error',
      };
    }
  }

  /**
   * Room Management API Endpoints
   */

  async createRoom(request: CreateRoomRequest): Promise<ApiResponse<CreateRoomResponse>> {
    return this.request<CreateRoomResponse>('/api/rooms/create', {
      method: 'POST',
      body: JSON.stringify(request),
    });
  }

  async joinRoom(request: JoinRoomRequest): Promise<ApiResponse<JoinRoomResponse>> {
    return this.request<JoinRoomResponse>(`/api/rooms/join/${request.room_id}`, {
      method: 'POST',
      body: JSON.stringify(request),
    });
  }

  async listRooms(): Promise<ApiResponse<ListRoomsResponse>> {
    return this.request<ListRoomsResponse>('/api/rooms/list', {
      method: 'GET',
    });
  }

  /**
   * Authentication API Endpoints
   */

  async login(request: AuthRequest): Promise<ApiResponse<AuthResponse>> {
    return this.request<AuthResponse>('/api/auth/login', {
      method: 'POST',
      body: JSON.stringify(request),
    });
  }

  async logout(): Promise<ApiResponse<string>> {
    return this.request<string>('/api/auth/logout', {
      method: 'POST',
    });
  }

  /**
   * Health Check
   */

  async healthCheck(): Promise<boolean> {
    try {
      const response = await fetch(`${this.baseUrl}`);
      return response.ok;
    } catch {
      return false;
    }
  }
}

// Export singleton instance
export const apiService = new ApiService();
export default apiService;

// Export types for use in components
export type {
  ApiResponse,
  CreateRoomRequest,
  CreateRoomResponse,
  JoinRoomRequest,
  JoinRoomResponse,
  RoomInfo,
  ListRoomsResponse,
  AuthRequest,
  AuthResponse,
};
