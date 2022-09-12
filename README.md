# Eidfs

Skeleton Phoenix Application w/ Github Actions, Earthly, and
VSCode devcontainer automation in place.

# Local Development

  * Install Erlang & Elixir
  * Install VSCode
  * Install Docker-for-Desktop
  * Install Earthly

# Containerized Development

  * Install VSCode
  * Install Docker-for-Desktop
  * Install the Remote Containers VSCode Extension
  
# How to Start the Application

To start your Phoenix server:

  * Install dependencies with `mix deps.get`
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) (HTTP) and/or
[`localhost:4001`](https://localhost:4001) (HTTPS) from your browser.

# How to Build and Test

First, ensure that all the values in the `.env` file are up to date.

```bash
# run tests + analyses
earthly +test

# build the docker scratch and alpine images + tar.gz
earthly +get-tag-from-branch --BUILD=+build --TAG=latest
```

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix
