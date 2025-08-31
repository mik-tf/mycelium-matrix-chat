import React, { useState, useEffect, useCallback } from 'react';
import { createClient, MatrixClient } from 'matrix-js-sdk';
import { Login } from './components/Login';
import { MessageList } from './components/MessageList';
import { MessageInput } from './components/MessageInput';
import { ConnectionStatus } from './components/ConnectionStatus';
import { MyceliumStatus } from './components/MyceliumStatus';
import { apiService } from './services/api';

function App() {
  const [user, setUser] = useState<any>(null);
  const [client, setClient] = useState<any>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [rooms, setRooms] = useState<any[]>([]);
  const [selectedRoom, setSelectedRoom] = useState<any>(null);
  const [newRoomName, setNewRoomName] = useState('');
  const [roomAliasOrId, setRoomAliasOrId] = useState('');

  // Debug states
  useEffect(() => {
    console.log('App Debug - State changed! user:', user);
    console.log('App Debug - State changed! isLoading:', isLoading);
    console.log('App Debug - State changed! client:', client ? 'exists' : 'null');
  }, [user, isLoading, client]);

  // Login function moved to App - now uses API service first
  const login = useCallback(async (username: string, password: string, serverName: string = 'matrix.org') => {
    console.log('🔌 API login starting...');
    setIsLoading(true);
    setError(null);

    try {
      // First, authenticate via our API gateway
      console.log('🔗 Calling API login...');
      const authResponse = await apiService.login({ username, password });

      if (!authResponse.success || !authResponse.data) {
        throw new Error(authResponse.error || 'API authentication failed');
      }

      console.log('✅ API login successful!', authResponse.data);

      // Now create Matrix client for message synchronization
      const matrixClient = createClient({
        baseUrl: `https://${serverName}`,
        accessToken: authResponse.data.access_token,
        userId: authResponse.data.user_id,
      });

      // Set state with API data
      const userData = {
        userId: authResponse.data.user_id,
        accessToken: authResponse.data.access_token,
        serverName,
        isApiAuthenticated: true,
      };

      console.log('👤 Setting user state:', userData);

      // Set state - should trigger re-render
      setUser(userData);
      setClient(matrixClient);

      await matrixClient.startClient();

      console.log('✅ Matrix sync started and completed');

    } catch (err: any) {
      console.error('❌ App login error:', err);
      setError(err.message || 'Authentication failed');
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

  // Debug logging for state changes
  useEffect(() => {
    console.log('App Debug - user:', user);
    console.log('App Debug - isLoading:', isLoading);
    console.log('App Debug - error:', error);
    console.log('App Debug - client:', client ? 'exists' : 'null');
  }, [user, isLoading, error, client]);

  // Force re-render when user state changes
  const [renderKey, setRenderKey] = useState(0);
  useEffect(() => {
    if (user && !isLoading) {
      console.log('🔄 Force re-render triggered by user state change');
      setRenderKey(prev => prev + 1);
    }
  }, [user, isLoading]);

  useEffect(() => {
    if (client) {
      const loadRooms = () => {
        const joinedRooms = client.getRooms();
        setRooms(joinedRooms);
      };
      loadRooms();
    }
  }, [client]);

  const createRoom = async () => {
    if (!newRoomName.trim()) return;

    console.log('🏗️ Creating room via API:', newRoomName);
    try {
      const response = await apiService.createRoom({
        room_name: newRoomName,
        is_public: false,
      });

      if (response.success && response.data) {
        console.log('✅ Room created:', response.data);
        // If Matrix client exists, try to join the room via Matrix
        if (client && response.data.room_id) {
          try {
            await client.joinRoom(response.data.room_id);
            console.log('✅ Joined room via Matrix client');
          } catch (err) {
            console.warn('⚠️ Matrix join failed, but room was created in database');
          }
        }
        setNewRoomName('');
      } else {
        console.error('❌ API room creation failed:', response.error);
        setError(response.error || 'Failed to create room');
      }
    } catch (err: any) {
      console.error('❌ Room creation failed:', err);
      setError(err.message || 'Failed to create room');
    }
  };

  const joinRoom = async () => {
    if (!roomAliasOrId.trim()) return;

    console.log('🚪 Joining room via API:', roomAliasOrId);
    try {
      const response = await apiService.joinRoom({
        room_id: roomAliasOrId,
      });

      if (response.success && response.data) {
        console.log('✅ Room join successful:', response.data);
        // If Matrix client exists, try to join via Matrix as well
        if (client && response.data.room_id) {
          try {
            await client.joinRoom(response.data.room_id);
            console.log('✅ Joined room via Matrix client');
          } catch (err) {
            console.warn('⚠️ Matrix join failed, but room was joined in API');
          }
        }
        setRoomAliasOrId('');
      } else {
        console.error('❌ API room join failed:', response.error);
        setError(response.error || 'Failed to join room');
      }
    } catch (err: any) {
      console.error('❌ Room join failed:', err);
      setError(err.message || 'Failed to join room');
    }
  };

  if (isLoading || (!user && client)) {
    return (
      <div className="min-h-screen bg-gray-100 flex items-center justify-center">
        <div className="bg-white p-8 rounded-lg shadow-md">
          <p className="text-gray-600">Loading...</p>
        </div>
      </div>
    );
  }

  if (!user) {
    return <Login onLogin={login} isLoading={isLoading} error={error} />;
  }

  return (
    <div key={`app-${user?.userId || 'guest'}-${renderKey}`} className="min-h-screen bg-gray-100 flex flex-col md:flex-row">
      <aside className="w-full md:w-64 bg-white shadow-md p-4 md:min-h-screen md:max-h-screen overflow-y-auto">
        <h2 className="text-lg font-bold mb-4">Rooms</h2>
        <div className="mb-4">
          <input
            type="text"
            placeholder="New room name"
            value={newRoomName}
            onChange={(e) => setNewRoomName(e.target.value)}
            className="w-full px-2 py-1 border border-gray-300 rounded mb-2"
          />
          <button onClick={createRoom} className="w-full bg-green-500 hover:bg-green-600 text-white py-1 rounded text-sm">
            Create Room
          </button>
        </div>
        <div className="mb-4">
          <input
            type="text"
            placeholder="Room alias or ID"
            value={roomAliasOrId}
            onChange={(e) => setRoomAliasOrId(e.target.value)}
            className="w-full px-2 py-1 border border-gray-300 rounded mb-2"
          />
          <button onClick={joinRoom} className="w-full bg-blue-500 hover:bg-blue-600 text-white py-1 rounded text-sm">
            Join Room
          </button>
        </div>
        <ul className="space-y-1">
          {rooms.map((room) => (
            <li key={room.roomId}>
              <button
                onClick={() => setSelectedRoom(room)}
                className={`w-full text-left px-2 py-1 rounded text-sm ${
                  selectedRoom?.roomId === room.roomId
                    ? 'bg-blue-100'
                    : 'hover:bg-gray-100'
                }`}
              >
                {room.name || room.roomId}
              </button>
            </li>
          ))}
        </ul>
      </aside>
      <div className="flex-1 flex flex-col">
        <header className="bg-white shadow p-4 flex flex-col md:flex-row justify-between items-start md:items-center space-y-2 md:space-y-0">
          <h1 className="text-lg md:text-xl font-bold text-gray-800">
            Mycelium Matrix Chat
          </h1>
          <div className="flex flex-wrap items-center space-x-2 md:space-x-4 w-full md:w-auto justify-between md:justify-end">
            <div className="flex items-center space-x-2">
              <ConnectionStatus />
              <MyceliumStatus client={client ?? undefined} room={selectedRoom ?? undefined} />
            </div>
            <div className="flex items-center space-x-2">
              <span className="text-xs md:text-sm text-gray-600 truncate max-w-32 md:max-w-none">
                {user.userId}
              </span>
              <button
                onClick={logout}
                className="bg-red-500 hover:bg-red-600 text-white px-2 md:px-3 py-1 rounded text-xs md:text-sm"
              >
                Logout
              </button>
            </div>
          </div>
        </header>
        <main className="flex-1 p-4">
          {selectedRoom ? (
            <div className="bg-white h-full rounded-lg shadow-md flex flex-col">
              <div className="p-4 border-b">
                <h3 className="text-lg font-semibold">{selectedRoom.name || selectedRoom.roomId}</h3>
              </div>
              {client && <MessageList room={selectedRoom} client={client} />}
              {client && <MessageInput room={selectedRoom} client={client} />}
            </div>
          ) : (
            <div className="bg-white p-8 rounded-lg shadow-md text-center">
              <p className="text-gray-600">
                Select a room to start chatting.
              </p>
            </div>
          )}
        </main>
      </div>
    </div>
  );
}

export default App;
