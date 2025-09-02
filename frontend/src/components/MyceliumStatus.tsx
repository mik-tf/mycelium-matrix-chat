import React, { useState, useEffect } from 'react';
import { MatrixClient, Room } from 'matrix-js-sdk';
import { myceliumService, MyceliumStatus as MyceliumStatusType } from '../services/mycelium';

interface MyceliumStatusProps {
  client?: MatrixClient;
  room?: Room;
}

export const MyceliumStatus: React.FC<MyceliumStatusProps> = ({ client, room }) => {
  const [myceliumStatus, setMyceliumStatus] = useState<MyceliumStatusType>({
    detected: false,
    connected: false,
  });
  const [networkHealth, setNetworkHealth] = useState<'excellent' | 'good' | 'fair' | 'poor' | 'offline'>('offline');

  useEffect(() => {
    // Check for Mycelium client API availability
    const checkMycelium = async () => {
      try {
        const status = await myceliumService.detectMycelium();
        setMyceliumStatus(status);

        if (status.detected) {
          const health = await myceliumService.getNetworkHealth();
          setNetworkHealth(health);
        } else {
          setNetworkHealth('offline');
        }
      } catch (error) {
        console.error('Mycelium detection failed:', error);
        setMyceliumStatus({
          detected: false,
          connected: false,
          error: error instanceof Error ? error.message : 'Unknown error',
        });
        setNetworkHealth('offline');
      }
    };

    checkMycelium();

    // Periodic check for Mycelium availability
    const interval = setInterval(checkMycelium, 30000); // Check every 30 seconds

    return () => clearInterval(interval);
  }, [client, room]);

  if (!myceliumStatus.detected) {
    return (
      <div className="flex items-center space-x-2 px-2 py-1 rounded-lg bg-gray-50 border border-gray-200">
        <div className="w-2 h-2 rounded-full bg-gray-400" />
        <span className="text-xs text-gray-600 font-medium">
          Standard Mode
        </span>
        <span className="text-xs text-gray-500">
          Mycelium not detected
        </span>
      </div>
    );
  }

  const getHealthColor = (health: string) => {
    switch (health) {
      case 'excellent': return 'bg-green-500';
      case 'good': return 'bg-blue-500';
      case 'fair': return 'bg-yellow-500';
      case 'poor': return 'bg-orange-500';
      default: return 'bg-gray-400';
    }
  };

  const getHealthBg = (health: string) => {
    switch (health) {
      case 'excellent': return 'bg-green-50 border-green-200';
      case 'good': return 'bg-blue-50 border-blue-200';
      case 'fair': return 'bg-yellow-50 border-yellow-200';
      case 'poor': return 'bg-orange-50 border-orange-200';
      default: return 'bg-gray-50 border-gray-200';
    }
  };

  const getHealthText = (health: string) => {
    switch (health) {
      case 'excellent': return 'text-green-700';
      case 'good': return 'text-blue-700';
      case 'fair': return 'text-yellow-700';
      case 'poor': return 'text-orange-700';
      default: return 'text-gray-600';
    }
  };

  return (
    <div className={`flex items-center space-x-2 px-2 py-1 rounded-lg border ${getHealthBg(networkHealth)}`}>
      <div className={`w-2 h-2 rounded-full animate-pulse ${getHealthColor(networkHealth)}`} />
      <span className={`text-xs font-medium ${getHealthText(networkHealth)}`}>
        Mycelium Enhanced
      </span>
      <span className="text-xs text-gray-600">
        {myceliumStatus.peers || 0} peers • {networkHealth} connection
      </span>
      {myceliumStatus.version && (
        <span className="text-xs text-gray-500">
          v{myceliumStatus.version}
        </span>
      )}
    </div>
  );
};

// Utility function for Mycelium feature detection
export const isMyceliumEnhanced = async (): Promise<boolean> => {
  // This would be used throughout the app to conditionally show Mycelium features
  try {
    const status = await myceliumService.detectMycelium();
    return status.detected && status.connected;
  } catch {
    return false;
  }
};
