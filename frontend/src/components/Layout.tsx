import { ConnectButton } from "@rainbow-me/rainbowkit";
import { Link, Outlet } from "react-router-dom";
import "./Layout.css";

function Layout() {
  return (
    <div>
      <nav className="navbar">
        <div className="nav-links">
          <Link to="/" className="nav-logo">NFT Marketplace</Link>
          <Link to="/create">Create</Link>
          <Link to="/staking">Staking</Link>
          <Link to="/auctions">Auctions</Link>
          <Link to="/collections">Collections</Link>
        </div>
        <ConnectButton />
      </nav>
      <main>
        <Outlet />
      </main>
    </div>
  );
}

export default Layout;
