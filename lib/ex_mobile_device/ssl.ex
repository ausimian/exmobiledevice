defmodule ExMobileDevice.Ssl do
  @moduledoc """
  SSL/TLS helper functions.

  This module contains a helper function, `connect/2` that can be used
  to authenticate an _existing_ `:gen_tcp` socket.
  """
  @legacy_sign_algos [
    sha: :rsa,
    sha: :ecdsa,
    sha256: :rsa,
    sha256: :ecdsa,
    sha384: :rsa,
    sha384: :ecdsa,
    sha512: :rsa,
    sha512: :ecdsa
  ]

  @doc """
  Authenticate an existing connection, using a pair-record.

  On success, returns an `:ssl` socket.
  """
  @spec connect(port(), map()) :: {:ok, :ssl.sslsocket()} | {:error, any()}
  def connect(socket, pair_record) when is_port(socket) and is_map(pair_record) do
    [{_, cert, _}] = :public_key.pem_decode(pair_record["HostCertificate"])
    [{key_type, key, _}] = :public_key.pem_decode(pair_record["HostPrivateKey"])

    :ssl.connect(socket,
      cert: cert,
      key: {key_type, key},
      verify: :verify_none,
      signature_algs: signature_algs()
    )
  end

  defp signature_algs do
    :ssl.signature_algs(:default, :"tlsv1.3") ++ @legacy_sign_algos
  end
end
