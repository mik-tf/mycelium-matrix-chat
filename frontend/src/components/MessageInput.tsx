import React, { useState, useRef } from 'react';
import { MatrixClient, Room, MsgType } from 'matrix-js-sdk';

interface MessageInputProps {
  room: Room;
  client: MatrixClient;
  onMessageSent?: () => void;
}

export const MessageInput: React.FC<MessageInputProps> = ({ room, client, onMessageSent }) => {
  const [message, setMessage] = useState('');
  const [sending, setSending] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  const handleSend = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!message.trim() || sending) return;

    setSending(true);
    try {
      await client.sendMessage(room.roomId, {
        msgtype: MsgType.Text,
        body: message.trim(),
      });

      setMessage('');
      if (onMessageSent) onMessageSent();
      inputRef.current?.focus();
    } catch (error) {
      console.error('Failed to send message:', error);
      // Could add error state here if needed
    } finally {
      setSending(false);
    }
  };

  const handleKeyPress = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSend(e as any);
    }
  };

  return (
    <div className="border-t p-4 bg-white">
      <form onSubmit={handleSend} className="flex space-x-3">
        <div className="flex-1">
          <input
            ref={inputRef}
            type="text"
            value={message}
            onChange={(e) => setMessage(e.target.value)}
            onKeyPress={handleKeyPress}
            placeholder="Type a message..."
            className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            disabled={sending}
          />
        </div>
        <button
          type="submit"
          disabled={!message.trim() || sending}
          className="px-6 py-2 bg-blue-500 hover:bg-blue-600 disabled:bg-blue-300 disabled:hover:bg-blue-300 text-white rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 transition-colors"
        >
          {sending ? 'Sending...' : 'Send'}
        </button>
      </form>
      <div className="mt-2 text-xs text-gray-500">
        Press Enter to send, Shift+Enter for new line
      </div>
    </div>
  );
};
