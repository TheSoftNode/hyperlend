Integrate ConnectKit with Somnia in a Next.js Application
In this guide, we'll integrate ConnectKit with the Somnia Network in a Next.js application. This will enable users to connect their wallets seamlessly, facilitating interactions with the Somnia blockchain.

Prerequisites
Before we begin, ensure you have the following:

This guide is not an introduction to JavaScript Programming; you are expected to understand JavaScript.

To complete this guide, you will need MetaMask installed and the Somnia DevNet added to the list of Networks. If you have yet to install MetaMask, please follow this guide to Connect Your Wallet guide.

Familiarity with React and Next.js is assumed.

Create the Next.js Project
Open your terminal and run the following commands to set up a new Next.js project:

Copy
npx create-next-app@latest somnia-connectkit
cd somnia-connectkit
Install the required Dependencies which are wagmi, viem, @tanstack/react-query, and connectkit. Run the following command:

Copy
npm install wagmi viem @tanstack/react-query connectkit
Set Up Providers in Next.js
We'll set up several providers to manage the application's state and facilitate interactions with the blockchain.

Create a components directory in the app folder. Inside the components directory, create a file named ClientProvider.tsx with the following content:

Copy
'use client';

import { WagmiConfig, createConfig } from 'wagmi';
import { ConnectKitProvider, getDefaultConfig } from 'connectkit';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { somniaTestnet } from 'viem/chains';

const queryClient = new QueryClient();

const config = createConfig(
getDefaultConfig({
autoConnect: true,
appName: 'Somnia DApp',
chains: [somniaTestnet],
})
);

export default function ClientProvider({ children }) {
return (
<WagmiConfig config={config}>
<QueryClientProvider client={queryClient}>
<ConnectKitProvider>{children}</ConnectKitProvider>
</QueryClientProvider>
</WagmiConfig>
);
}
In the app directory, locate the layout.tsx file and update it as follows:

Copy
import ClientProvider from './components/ClientProvider';
export default function RootLayout({ children }) {
return (
<html lang="en">
<head>
<title>Somnia DApp</title>
<meta name="viewport" content="width=device-width, initial-scale=1" />
</head>
<body>
<ClientProvider>{children}</ClientProvider>
</body>
</html>
);
}
Build the Home Page
We'll create a simple home page that allows users to connect their wallets and displays their address upon connection.

In the app directory, locate the page.tsx file and update it as follows:

Copy
'use client';

import { useAccount } from 'wagmi';
import { ConnectKitButton } from 'connectkit';

export default function Home() {
const { address, isConnected } = useAccount();
return (
<div className="grid grid-rows-[20px_1fr_20px] items-center justify-items-center min-h-screen p-8 pb-20 gap-16 sm:p-20 font-[family-name:var(--font-geist-sans)]">
<main className="flex flex-col gap-8 row-start-2 items-center sm:items-start">
Hello, world!
{/_ Connect Button _/}
<div className="mt-4">
<ConnectKitButton />
</div>
{/_ Show Wallet Address _/}
{isConnected && (
<p className="mt-4 text-lg text-blue-600">Connected as: {address}</p>
)}
</main>
</div>
);
}
To run the application, start the Development Server by running the following command:

Copy
npm run dev
Open your browser and navigate to http://localhost:3000. You should see the ConnectKit button, allowing users to connect their wallets to the Somnia network.

Conclusion
You've successfully integrated ConnectKit with the Somnia Network in a Next.js application. This setup provides a foundation for building decentralized applications on Somnia, enabling seamless wallet connections and interactions with the Somnia Network.

For further exploration, consider adding features such as interacting with smart contracts, displaying user balances, or implementing transaction functionalities.
