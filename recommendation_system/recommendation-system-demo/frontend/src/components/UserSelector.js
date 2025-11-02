import React from 'react';

const UserSelector = ({ users, selectedUser, onUserSelect }) => {
  return (
    <div className="user-selector">
      <label style={{ color: 'white', fontWeight: '600' }}>Select User:</label>
      <select 
        value={selectedUser?.id || ''} 
        onChange={(e) => {
          const user = users.find(u => u.id === parseInt(e.target.value));
          onUserSelect(user);
        }}
        style={{
          padding: '0.5rem 1rem',
          border: 'none',
          borderRadius: '8px',
          background: 'white',
          fontSize: '1rem'
        }}
      >
        {users.map(user => (
          <option key={user.id} value={user.id}>
            {user.username} ({user.email})
          </option>
        ))}
      </select>
    </div>
  );
};

export default UserSelector;
