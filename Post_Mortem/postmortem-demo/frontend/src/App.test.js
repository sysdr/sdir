import { render, screen } from '@testing-library/react';
import App from './App';

test('renders navigation', () => {
  render(<App />);
  const navElement = screen.getByText(/PostMortem Pro/i);
  expect(navElement).toBeInTheDocument();
});
