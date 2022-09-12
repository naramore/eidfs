defmodule EidfsWeb.PageController do
  use EidfsWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
