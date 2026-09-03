return {
  {
    "stevearc/conform.nvim",
    event = "BufWritePre",
    opts = require "configs.conform",
  },

  -- These are some examples, uncomment them if you want to see them work!
  {
    "neovim/nvim-lspconfig",
    config = function()
      require "configs.lspconfig"
    end,
  },

  {
  	"nvim-treesitter/nvim-treesitter",
  	branch = "main",
  	opts = {
  		ensure_installed = {
  			"vim", "lua", "vimdoc",
        "html", "css", "javascript", "typescript",
        "json", "csv", "cue",
        "go", "proto", "bash", "make",
        "python", "rust"
  		},
  	},
  },

  {
    "olexsmir/gopher.nvim",
    ft = "go",
    config = function(_, opts)
     require("gopher").setup(opts)
     --require("core.utils").load_mappings("gopher")
    end,
    build = function()
     vim.cmd [[silent! GoInstallDeps]]
    end,
  },

  {
    "christoomey/vim-tmux-navigator",
    lazy=false,
    cmd = {
      "TmuxNavigateLeft",
      "TmuxNavigateDown",
      "TmuxNavigateUp",
      "TmuxNavigateRight",
      "TmuxNavigatePrevious",
    },
    keys = {
      { "<c-h>", "<cmd><C-U>TmuxNavigateLeft<cr>" },
      { "<c-j>", "<cmd><C-U>TmuxNavigateDown<cr>" },
      { "<c-k>", "<cmd><C-U>TmuxNavigateUp<cr>" },
      { "<c-l>", "<cmd><C-U>TmuxNavigateRight<cr>" },
      { "<c-\\>", "<cmd><C-U>TmuxNavigatePrevious<cr>" },
    },
  },
}
