defmodule DCache.Tests.Cache do
	require DCache
	DCache.define(Users, 100, purger: :no_spawn)

	DCache.define(Products, 10, segments: 2, purger: &DCache.Tests.Cache.custom_purger/1)

	def custom_purger(segment) do
		:ets.update_counter(segment, :purger, {2, 1}, {:purger, 1})
	end
end
