import { BrowserRouter, Routes, Route } from "react-router-dom";
import Layout from "./components/Layout";
import HomePage from "./pages/HomePage";
import CreateCollection from "./pages/CreateCollection";
import CollectionsPage from "./pages/CollectionsPage";
import StakingPage from "./pages/StakingPage";
import AuctionsPage from "./pages/AuctionsPage";


function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route element={<Layout />}>
          <Route path="/" element={<HomePage />} />
          <Route path="/create" element={<CreateCollection />} />
          <Route path="/collection/:id" element={<CollectionPage />} />
          <Route path="/staking" element={<StakingPage />} />
          <Route path="/auctions" element={<AuctionsPage />} />
          <Route path="/collections" element={<CollectionsPage />} /> 
        </Route>
      </Routes>
    </BrowserRouter>
  );
}

export default App;