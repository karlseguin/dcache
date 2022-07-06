defmodule DCache.Tests.DCache do
	use DCache.Tests
	alias DCache.Tests.Cache.Users, as: UserCache

	setup_all do
		:ok = UserCache.setup()
		:ok = DCache.setup(:users, 100)
		:ok
	end

	describe "defined" do
		test "get / put" do
			assert UserCache.get("k") == nil

			assert UserCache.put("k", 1, 10) == :ok
			assert UserCache.get("k") == {:ok, 1}

			assert UserCache.put("k", 2, 10) == :ok
			assert UserCache.get("k") == {:ok, 2}

			assert UserCache.put("stale", 3, -10) == :ok
			assert UserCache.get("stale") == nil
		end

		test "fetch" do
			assert UserCache.put("fetch", 4, 10) == :ok
			assert UserCache.fetch("fetch", nil, 100) == {:ok, 4}

			assert UserCache.put("fetch", 5, -10) == :ok
			assert UserCache.fetch!("fetch", fn key ->
				{:ok, key <> "x"}
			end, 100) == "fetchx"
			assert UserCache.get("fetch") == {:ok, "fetchx"}

			assert UserCache.fetch("fetch2", fn _key ->
				{:skip, "nope"}
			end, 100) == "nope"
			assert UserCache.get("fetch2") == nil

			assert UserCache.fetch("fetch3", fn _key ->
				{:error, "nope2"}
			end, 100) == {:error, "nope2"}
			assert UserCache.get("fetch3") == nil

			assert UserCache.fetch("fetch4", fn _key ->
				{:ok, "explicit ttl", 5}
			end, nil) == {:ok, "explicit ttl"}
			assert_in_delta UserCache.expires("fetch4"), :erlang.system_time(:second) + 5, 1

			assert_raise RuntimeError, fn ->
				UserCache.fetch!("fail", fn _key -> {:error, "fail"} end)
			end

			assert UserCache.fetch!("key3", fn key -> {:skip, "other:#{key}"} end) == "other:key3"
		end

		test "del" do
			assert UserCache.del("del") == false

			assert UserCache.put("del", "a", 10) == :ok
			assert UserCache.get("del") == {:ok, "a"}

			assert UserCache.del("del") == true
			assert UserCache.get("del") == nil
		end

		test "take" do
			assert UserCache.take("take") == nil

			assert UserCache.put("take", "b", 10) == :ok
			assert UserCache.get("take") == {:ok, "b"}

			assert {:ok, {"take", "b", expires}} = UserCache.take("take")
			assert_in_delta expires, :erlang.system_time(:second) + 10, 1
			assert UserCache.get("take") == nil
		end

		test "prune on put" do
			for i <- 1..1001 do
				assert UserCache.put(to_string(i), i, 100) == :ok
			end
			assert UserCache.size() < 950
		end
	end

	describe "dynamic" do
		test "get / put" do
			assert DCache.get(:users, "k") == nil

			assert DCache.put(:users, "k", 1, 10) == :ok
			assert DCache.get(:users, "k") == {:ok, 1}

			assert DCache.put(:users, "k", 2, 10) == :ok
			assert DCache.get(:users, "k") == {:ok, 2}

			assert DCache.put(:users, "stale", 3, -10) == :ok
			assert DCache.get(:users, "stale") == nil
		end

		test "fetch" do
			assert DCache.put(:users, "fetch", 4, 10) == :ok
			assert DCache.fetch(:users, "fetch", nil, 100) == {:ok, 4}

			assert DCache.put(:users, "fetch", 5, -10) == :ok
			assert DCache.fetch!(:users, "fetch", fn key ->
				{:ok, key <> "x"}
			end, 100) == "fetchx"
			assert DCache.get(:users, "fetch") == {:ok, "fetchx"}

			assert DCache.fetch(:users, "fetch2", fn _key ->
				{:skip, "nope"}
			end, 100) == "nope"
			assert DCache.get(:users, "fetch2") == nil

			assert DCache.fetch(:users, "fetch3", fn _key ->
				{:error, "nope2"}
			end, 100) == {:error, "nope2"}
			assert DCache.get(:users, "fetch3") == nil

			assert DCache.fetch(:users, "fetch4", fn _key ->
				{:ok, "explicit ttl", 5}
			end, nil) == {:ok, "explicit ttl"}
			assert_in_delta DCache.expires(:users, "fetch4"), :erlang.system_time(:second) + 5, 1

			assert_raise RuntimeError, fn ->
				DCache.fetch!(:users, "fail", fn _key -> {:error, "fail"} end)
			end

			assert DCache.fetch!(:users, "key3", fn key -> {:skip, "other:#{key}"} end) == "other:key3"
		end

		test "del" do
			assert DCache.del(:users, "del") == false

			assert DCache.put(:users, "del", "a", 10) == :ok
			assert DCache.get(:users, "del") == {:ok, "a"}

			assert DCache.del(:users, "del") == true
			assert DCache.get(:users, "del") == nil
		end

		test "take" do
			assert DCache.take(:users, "take") == nil

			assert DCache.put(:users, "take", "b", 10) == :ok
			assert DCache.get(:users, "take") == {:ok, "b"}

			assert {:ok, {"take", "b", expires}} = DCache.take(:users, "take")
			assert_in_delta expires, :erlang.system_time(:second) + 10, 1
			assert DCache.get(:users, "take") == nil
		end

		test "prune on put" do
			for i <- 1..1001 do
				assert DCache.put(:users, to_string(i), i, 100) == :ok
			end
			assert DCache.size(:users) < 950
		end
	end
end
