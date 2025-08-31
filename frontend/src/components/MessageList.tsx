import React, { useEffect, useState } from 'react';
import { MatrixClient, Room, MessageEventContent, MsgType } from 'matrix-js-sdk';

interface Message {
  id: string;
  sender: string;
  content: string;
  timestamp: number;
  type: string;
}

interface MessageListProps {
  room: Room;
  client: MatrixClient;
}

export const MessageList: React.FC<MessageListProps> = ({ room, client }) => {
  const [messages, setMessages] = useState<Message[]>([]);
  const [loading, setLoading] = useState(false);

  // Load initial messages from room timeline
  useEffect(() => {
    const loadMessages = async () => {
      if (!room || !client) return;

      setLoading(true);
      try {
        const timeline = room.getTimeline();
        if (timeline) {
          const messagesFromTimeline: Message[] = [];
          for (const event of timeline.getEvents()) {
            if (event.getType() === 'm.room.message') {
              const content = event.getContent() as MessageEventContent;
              messagesFromTimeline.push({
                id: event.getId()!,
                sender: event.getSender()!,
                content: content.body || '',
                timestamp: event.getTs(),
                type: content.msgtype || 'm.text',
              });
            }
          }
          setMessages(messagesFromTimeline.reverse()); // Reverse to show chronological order
        }
      } catch (error) {
        console.error('Failed to load timeline:', error);
      } finally {
        setLoading(false);
      }
    };

    loadMessages();
  }, [room, client]);

  // Listen for new messages
  useEffect(() => {
    if (!client || !room) return;

    const handleRoomTimeline = (event: any, room: Room) => {
      if (room.roomId !== room.roomId) return;

      if (event.getType() === 'm.room.message') {
        const content = event.getContent() as MessageEventContent;
        const newMessage: Message = {
          id: event.getId()!,
          sender: event.getSender()!,
          content: content.body || '',
          timestamp: event.getTs(),
          type: content.msgtype || 'm.text',
        };

        setMessages(prev => [...prev, newMessage]);
      }
    };

    client.on('Room.timeline', handleRoomTimeline);

    return () => {
      client.off('Room.timeline', handleRoomTimeline);
    };
  }, [client, room]);

  const formatTime = (timestamp: number) => {
    return new Date(timestamp).toLocaleTimeString([], {
      hour: '2-digit',
      minute: '2-digit'
    });
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-full text-gray-500">
        Loading messages...
      </div>
    );
  }

  return (
    <div className="flex-1 overflow-y-auto p-4 space-y-3">
      {messages.length === 0 ? (
        <div className="text-center text-gray-500 py-8">
          No messages yet. Start the conversation!
        </div>
      ) : (
        messages.map((message) => (
          <div key={message.id} className="flex space-x-3">
            <div className="flex-shrink-0">
              <div className="w-8 h-8 bg-blue-500 rounded-full flex items-center justify-center text-white text-sm font-medium">
                {message.sender.charAt(1).toUpperCase()}
              </div>
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex items-center space-x-2 mb-1">
                <span className="font-medium text-gray-900 text-sm">
                  {message.sender.split(':')[0].slice(1)}
                </span>
                <span className="text-xs text-gray-500">
                  {formatTime(message.timestamp)}
                </span>
              </div>
              <div className="text-gray-700 break-words">
                {message.content}
              </div>
            </div>
          </div>
        ))
      )}
    </div>
  );
};
