import { createClient, MatrixClient } from 'matrix-js-sdk';
import { useState, useEffect, useCallback } from 'react';

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

  // Load user from localStorage on mount
  useEffect(() => {
    const stored = localStorage.getItem('matrix_user');
    if (stored) {
      const storedUser: MatrixUser = JSON.parse(stored);
      setUser(storedUser);
      // Recreate client
      const matrixClient = createClient({
        baseUrl: `http://localhost:8080/_matrix`,
        accessToken: storedUser.accessToken,
        userId: storedUser.userId,
        deviceId: storedUser.deviceId,
      });
      setClient(matrixClient);
    }
  }, []);

  const login = useCallback(async (username: string, password: string, serverName: string = 'matrix.org') => {
    setIsLoading(true);
    setError(null);
    try {
      const matrixClient = createClient({ baseUrl: `http://localhost:8080/_matrix` });

      const loginResponse = await matrixClient.login('m.login.password', {
        user: username,
        password,
        initial_device_display_name: 'Mycelium Matrix Chat',
      });

      const user: MatrixUser = {
        userId: loginResponse.user_id!,
        accessToken: loginResponse.access_token!,
        deviceId: loginResponse.device_id!,
        serverName,
      };

      setUser(user);
      setClient(matrixClient);
      localStorage.setItem('matrix_user', JSON.stringify(user));

      // Start sync
      await matrixClient.startClient();
    } catch (err: any) {
      setError(err.message || 'Login failed');
    } finally {
      setIsLoading(false);
    }
  }, []);

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
  };
};
