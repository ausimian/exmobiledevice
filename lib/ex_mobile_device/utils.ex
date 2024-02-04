defmodule ExMobileDevice.Utils do
  @moduledoc false
  def to_plist(v) do
    [~s(<plist version="1.0">), to_plist_value(v), "</plist>"]
  end

  defp to_plist_value(dict) when is_map(dict) do
    entries =
      Enum.reduce(dict, [], fn {k, v}, iodata ->
        [iodata, "<key>#{k}</key>", to_plist_value(v)]
      end)

    ["<dict>", entries, "</dict>"]
  end

  defp to_plist_value(v) when is_binary(v), do: "<string>#{v}</string>"
  defp to_plist_value(v) when is_integer(v), do: "<integer>#{v}</integer>"
  defp to_plist_value(true), do: "<true/>"
  defp to_plist_value(false), do: "<false/>"
end
