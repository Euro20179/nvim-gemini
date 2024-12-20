# Neovim Gemini client

An extremely basic neovim gemini client

# Dependancies

[gmni](https://git.sr.ht/~sircmpwn/gmni)

# Setup

```lua
local g = require"gemini"
g.setup{}
```

Now, whenever you enter a `gemini://` file it will actually open it

# Usage

open a `gemini://` url with nvim

to follow links use `gf`

## Certificates

To add certificates for a domain add the following to the setup table

```lua
{
    ["domain.example.com"] = {
        key = "~/path/to/key-file.pem",
        cert = "~/path/to/cert-file.pem"
    }
}
```
