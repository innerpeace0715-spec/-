import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
import ErrorBoundary from './ErrorBoundary';
// U-file uses a serif face throughout; bundled so the tablet needs no download.
import '@fontsource/noto-serif-kr/400.css';
import '@fontsource/noto-serif-kr/700.css';
import './styles.css';
createRoot(document.getElementById('root')!).render(<StrictMode><ErrorBoundary><App /></ErrorBoundary></StrictMode>);
