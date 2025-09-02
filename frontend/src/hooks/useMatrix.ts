import { createClient, MatrixClient } from 'matrix-js-sdk';
import { useState, useEffect, useCallback } from 'react';
import { myceliumService } from '../services/mycelium';

export interface MatrixUser {
  userId: string;
  accessToken: string;
  deviceId: string;
  serverName: string;
}

export const useMatrix = () => {
  const [client, setClient] = useState<MatrixClient | null>(null);
  const [user, setUser] = useState<MatrixUser | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [myceliumDetected, setMyceliumDetected] = useState(false);
  const [connectionMode, setConnectionMode] = useState<'standard' | 'enhanced'>('standard');

  // Load user from localStorage on mount and detect Mycelium
  useEffect(() => {
    const initialize = async () => {
      // Detect Mycelium availability
      try {
        const myceliumStatus = await myceliumService.detectMycelium();
        setMyceliumDetected(myceliumStatus.detected);
        setConnectionMode(myceliumStatus.detected ? 'enhanced' : 'standard');
      } catch (error) {
        console.error('Mycelium detection failed:', error);
        setMyceliumDetected(false);
        setConnectionMode('standard');
      }

      // Load stored user
      const stored = localStorage.getItem('matrix_user');
      if (stored) {
        const storedUser: MatrixUser = JSON.parse(stored);
        setUser(storedUser);
        // Recreate client with appropriate base URL based on Mycelium availability
        const baseUrl = myceliumDetected
          ? 'http://localhost:8081' // Use Matrix Bridge for enhanced mode
          : `https://${storedUser.serverName}`; // Direct connection for standard mode

        const matrixClient = createClient({
          baseUrl,
          accessToken: storedUser.accessToken,
          userId: storedUser.userId,
          deviceId: storedUser.deviceId,
        });
        setClient(matrixClient);
      }
    };

    initialize();
  }, [myceliumDetected]);

  const login = useCallback(async (username: string, password: string, serverName: string = 'matrix.org') => {
    console.log('🔌 Starting login process...');
    setIsLoading(true);  // Force loading state
    setError(null);      // Clear any previous errors

    try {
      // Determine connection mode based on Mycelium availability
      const currentMyceliumStatus = await myceliumService.detectMycelium();
      const useEnhancedMode = currentMyceliumStatus.detected;
      setMyceliumDetected(useEnhancedMode);
      setConnectionMode(useEnhancedMode ? 'enhanced' : 'standard');

      // Use Matrix Bridge for enhanced mode, direct connection for standard mode
      const baseUrl = useEnhancedMode
        ? 'http://localhost:8081' // Route through Matrix Bridge
        : `https://${serverName}`; // Direct connection to homeserver

      console.log('🌐 Creating Matrix client with baseUrl:', baseUrl, `(Mode: ${connectionMode})`);
      const matrixClient = createClient({ baseUrl });

      console.log('🔐 Attempting login...');
      const loginResponse = await matrixClient.login('m.login.password', {
        user: username,
        password,
        initial_device_display_name: 'Mycelium Matrix Chat',
      });

      console.log('✅ Login successful:', loginResponse);

      // Create new user object to ensure reference changes
      const userData: MatrixUser = {
        userId: loginResponse.user_id!,
        accessToken: loginResponse.access_token!,
        deviceId: loginResponse.device_id!,
        serverName,
      };

      console.log('👤 About to set user state:', userData);

      // Force synchronous state updates
      setUser(userData);
      setClient(matrixClient);

      // Verify state was set (this should help debug)
      setTimeout(() => {
        console.log('🔥 Delayed check - user state should be set now');
      }, 100);

      // Store in localStorage AFTER state is set
      localStorage.setItem('matrix_user', JSON.stringify(userData));

      console.log('🔄 Starting Matrix sync...');
      await matrixClient.startClient();
      console.log('✅ Matrix sync started successfully');

      // Set loading to false AFTER sync started
      setIsLoading(false);

    } catch (err: any) {
      console.error('❌ Login error:', err);
      setError(err.message || 'Login failed - check console for details');
      setIsLoading(false);
    }
  }, [connectionMode]);

  const logout = useCallback(async () => {
    if (client) {
      await client.logout();
      setClient(null);
      setUser(null);
      localStorage.removeItem('matrix_user');
    }
  }, [client]);

  return {
    client,
    user,
    isLoading,
    error,
    login,
    logout,
    myceliumDetected,
    connectionMode,
  };
};
