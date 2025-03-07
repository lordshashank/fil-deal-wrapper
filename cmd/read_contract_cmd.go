package cmd

import (
	"context"
	"fmt"
	"strconv"

	"github.com/eastore-project/fil-deal-wrapper/internal/contract"
	"github.com/eastore-project/fil-deal-wrapper/internal/eth"

	"github.com/urfave/cli/v2"
)

// commonReadFlags defines the shared flags for all contract read commands
var commonReadFlags = []cli.Flag{
	&cli.StringFlag{
		Name:     "contract-address",
		Aliases:  []string{"c"},
		Usage:    "MarketDealWrapper contract address",
		Value:    "0xYourDefaultContractAddress",
		Required: true,
	},
	&cli.StringFlag{
		Name:    "abi-path",
		Aliases: []string{"b"},
		Usage:   "Path to the contract ABI file",
		Value:   "./contracts/out/MarketDealWrapper.sol/MarketDealWrapper.json",
	},
	&cli.StringFlag{
		Name:    "rpc-url",
		Aliases: []string{"r"},
		Usage:   "RPC URL for the Ethereum node (overrides .env)",
	},
}
var ReadContractCmd = &cli.Command{
	Name:    "read-contract",
	Aliases: []string{"r"},
	Usage:   "Read data from the MarketDealWrapper contract",
	Subcommands: []*cli.Command{
		{
			Name:      "get-sp-id", 
			Aliases:   []string{"g"},
			Usage:     "Get Storage Provider address by Actor ID from the MarketDealWrapper contract",
			ArgsUsage: "<actor-id>",
			Flags:     commonReadFlags,
			Action: func(c *cli.Context) error {
				ctx := context.Background()
				actorIdStr := c.Args().Get(0)
				if actorIdStr == "" {
					return fmt.Errorf("missing actor-id argument")
				}
				actorId, err := strconv.ParseUint(actorIdStr, 10, 64)
				if err != nil {
					return fmt.Errorf("invalid actor-id: %v", err)
				}

				client, err := eth.NewETHClient(
					ctx,
					c,
				)
				if err != nil {
					return err
				}

				_, err = contract.GetSpFromIdAction(ctx, client, actorId)
				return err
			},
		},

		{
			Name:      "get-deals-from-miner-id", 
			Aliases:   []string{"gdfm"},
			Usage:     "Retrieve deal IDs associated with a given miner ID from the MarketDealWrapper contract",
			ArgsUsage: "<miner-id>",
			Flags:     commonReadFlags,
			Action: func(c *cli.Context) error {
				ctx := context.Background()
				minerIdStr := c.Args().Get(0)
				if minerIdStr == "" {
					return fmt.Errorf("missing miner-id argument")
				}
				minerId, err := strconv.ParseUint(minerIdStr, 10, 64)
				if err != nil {
					return fmt.Errorf("invalid miner-id: %v", err)
				}

				client, err := eth.NewETHClient(
					ctx,
					c,
				)
				if err != nil {
					return err
				}

				return contract.GetDealsFromMinerIdAction(ctx, client, minerId)
			},
		},
		{
			Name:      "is-whitelisted",
			Aliases:   []string{"iw"},
			Usage:     "Check if an address is whitelisted in the MarketDealWrapper contract",
			ArgsUsage: "<address>",
			Flags:     commonReadFlags,
			Action: func(c *cli.Context) error {
				ctx := context.Background()
				actorIdStr := c.Args().Get(0)
				if actorIdStr == "" {
					return fmt.Errorf("missing actor-id argument")
				}
				actorId, err := strconv.ParseUint(actorIdStr, 10, 64)
				if err != nil {
					return fmt.Errorf("invalid actor-id: %v", err)
				}

				client, err := eth.NewETHClient(
					ctx,
					c,
				)
				if err != nil {
					return err
				}
				return contract.IsWhitelistedAction(ctx, client, actorId)
			},
		},
		{
			Name:      "get-sp-funds-for-deal", 
			Aliases:   []string{"gsffd"},
			Usage:     "Retrieve the currently claimable SP funds for a specific deal from the MarketDealWrapper contract",
			ArgsUsage: "<deal-id>",
			Flags:     commonReadFlags,
			Action: func(c *cli.Context) error {
				ctx := context.Background()
				dealIdStr := c.Args().Get(0)
				if dealIdStr == "" {
					return fmt.Errorf("missing deal-id argument")
				}
				dealId, err := strconv.ParseUint(dealIdStr, 10, 64)
				if err != nil {
					return fmt.Errorf("invalid deal-id: %v", err)
				}

				client, err := eth.NewETHClient(
					ctx,
					c,
				)
				if err != nil {
					return err
				}

				return contract.GetSpFundsForDealAction(ctx, client, dealId)
			},
		},
		{
			Name:      "get-token-funds-for-sp",
			Aliases:   []string{"gtfsp"},
			Usage:     "Retrieve the currently claimable SP funds for a specific ERC20 token and actor ID",
			Flags:     commonReadFlags,
			ArgsUsage: "<token> <actor-id>",
			Action: func(c *cli.Context) error {
				ctx := context.Background()
				token := c.Args().Get(0)
				actorIdStr := c.Args().Get(1)
				if token == "" || actorIdStr == "" {
					return fmt.Errorf("missing token or actor-id argument")
				}
				actorId, err := strconv.ParseUint(actorIdStr, 10, 64)
				if err != nil {
					return fmt.Errorf("invalid actor-id: %v", err)
				}
				client, err := eth.NewETHClient(ctx, c)
				if err != nil {
					return err
				}
				return contract.GetTokenFundsForSPAction(ctx, client, token, actorId)
			},
		},
	},
}
