import React, { useState, useEffect } from 'react';

interface ConnectionStatusProps {
  isConnected?: boolean;
}

export const ConnectionStatus: React.FC<ConnectionStatusProps> = ({ isConnected = false }) => {
  const [connectionState, setConnectionState] = useState<'online' | 'offline' | 'connecting'>('connecting');

  useEffect(() => {
    // Simulate connection check to Web Gateway every 10 seconds
    const checkConnection = async () => {
      try {
        const response = await fetch('http://localhost:8080/health', {
          method: 'GET',
          headers: { 'Content-Type': 'application/json' },
        });

        if (response.ok) {
          setConnectionState('online');
        } else {
          setConnectionState('offline');
        }
      } catch (error) {
        setConnectionState('offline');
      }
    };

    checkConnection();
    const interval = setInterval(checkConnection, 10000); // Check every 10 seconds

    return () => clearInterval(interval);
  }, []);

  const getStatusColor = () => {
    switch (connectionState) {
      case 'online':
        return 'text-green-600 bg-green-100';
      case 'connecting':
        return 'text-yellow-600 bg-yellow-100';
      case 'offline':
        return 'text-red-600 bg-red-100';
    }
  };

  const getStatusText = () => {
    switch (connectionState) {
      case 'online':
        return 'Online';
      case 'connecting':
        return 'Connecting...';
      case 'offline':
        return 'Offline';
    }
  };

  return (
    <div className="flex items-center space-x-2 px-3 py-1 rounded-full text-sm">
      <div className={`w-2 h-2 rounded-full ${connectionState === 'online' ? 'bg-green-500' :
        connectionState === 'connecting' ? 'bg-yellow-500' : 'bg-red-500'}`} />
      <span className={getStatusColor()}>
        {getStatusText()}
      </span>
    </div>
  );
};
