import React, { useState, useEffect } from 'react';
import { MatrixClient, Room } from 'matrix-js-sdk';

interface MyceliumStatusProps {
  client?: MatrixClient;
  room?: Room;
}

export const MyceliumStatus: React.FC<MyceliumStatusProps> = ({ client, room }) => {
  const [myceliumAvailable, setMyceliumAvailable] = useState<boolean>(false);
  const [enhancedMode, setEnhancedMode] = useState<boolean>(false);

  useEffect(() => {
    // Check for Mycelium client API availability
    // This is a progressive enhancement check
    const checkMycelium = async () => {
      try {
        // Check if we're running on a Mycelium-enabled network
        // This simulates the detection of Mycelium's P2P capabilities
        const isMyceliumNetwork = () => {
          // In a real implementation, this would check:
          // 1. Local Mycelium daemon availability
          // 2. Presence of Mycelium JavaScript API bindings
          // 3. Network topology analysis

          // For now, we'll simulate detection
          return false; // Set to true to simulate Mycelium availability
        };

        const available = isMyceliumNetwork();
        setMyceliumAvailable(available);

        // Enhanced mode also depends on room and client state
        if (available && client && room) {
          // Check if current Matrix server supports Mycelium federation
          const enhanced = true; // In real impl, check server capabilities
          setEnhancedMode(enhanced);
        } else {
          setEnhancedMode(false);
        }
      } catch (error) {
        setMyceliumAvailable(false);
        setEnhancedMode(false);
      }
    };

    checkMycelium();

    // Periodic check for Mycelium availability
    const interval = setInterval(checkMycelium, 30000); // Check every 30 seconds

    return () => clearInterval(interval);
  }, [client, room]);

  if (!myceliumAvailable) {
    return null; // Don't show anything if Mycelium isn't available
  }

  return (
    <div className="flex items-center space-x-2 px-2 py-1 rounded-lg bg-green-50 border border-green-200">
      <div className="w-2 h-2 rounded-full bg-green-500 animate-pulse" />
      <span className="text-xs text-green-700 font-medium">
        {enhancedMode ? 'Mycelium Enhanced' : 'Mycelium Detected'}
      </span>
      {enhancedMode && (
        <span className="text-xs text-green-600">
          ✓ Direct P2P routing active
        </span>
      )}
    </div>
  );
};

// Utility function for Mycelium feature detection
export const isMyceliumEnhanced = (): boolean => {
  // This would be used throughout the app to conditionally show Mycelium features
  try {
    // Check for Mycelium API or library availability
    return typeof window !== 'undefined' &&
           (window as any).mycelium !== undefined;
  } catch {
    return false;
  }
};
