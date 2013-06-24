-- websocket support adaptded from lua-websocket (http://lipp.github.io/lua-websockets/)
-- WARN: incomplete, just enough to support lumen's websockets signaling

local has_bit32,bit32 = pcall(require,'bit32')
if  has_bit32 then
-- lua 5.2
	return bit32
else
-- luajit / lua 5.1 + luabitop
	local has_bit,bit = pcall(require,'bit')
	if has_bit then
		return bit
	else
		local has_nixio,nixio = pcall(require,'nixio')
		if has_nixio then
			local nbit =nixio.bit
			local nband = nbit.band
			local nbnot = nbit.bnot
			local ncheck = nbit.check
			local nbor = nbit.bor
			local nbxor = nbit.bxor
			local mybit = {}
			local sgn32mask = 2^31
			local all32mask = 2^32-1
			--32 bit implementation of rol and ror
			local function fix_sign_32(out)
				if ncheck(out, sgn32mask) then
					return -nband(nbnot(out-1), all32mask)
				else
					return out
				end
			end

			--[[
			mybit.rol = function(x, n)
				if n>15 then
					local  ret = mybit.rol(mybit.rol(x, n-15), 15)
					return ret
				end
				if x<0 then x=nbnot(-x)+1 end
				x = nband(x, all32mask)
				local out1 = nbit.lshift(x, n)
				local out2 = nbit.rshift(x, 32-n)
				out1=nband(out1, all32mask)
				out2=nband(out2, all32mask)
				local ret = fix_sign_32(nbor(out1, out2))
				return ret
			end
			mybit.ror = function(x, n)
				if n>15 then
					local  ret = mybit.ror(mybit.ror(x, n-15), 15)
					return ret
				end
				if x<0 then x=nbnot(-x)+1 end
				x = nband(x, all32mask)
				local out1 = nbit.rshift(x, n)
				local out2 = nband(x, 2^n-1)
				out1=nband(out1, all32mask)
				out2 = nbit.lshift(out2, 32-n)
				local ret = fix_sign_32(nbor(out1, out2)) 
				return ret
			end
			--]]

			mybit.bnot = function(a)
				local ret = fix_sign_32(nband(nbnot(a), all32mask))
				return ret
			end
			mybit.band = function(a, b)
				a=nband(a, all32mask)
				b=nband(b, all32mask)
				local ret = fix_sign_32(nband(nband(a, b),all32mask))
				return ret
			end
			mybit.bor = function(a,b)
				a=nband(a, all32mask)
				b=nband(b, all32mask)
				local ret = fix_sign_32(nbor(a, b))
				return ret
			end
			mybit.bxor = function(a,b)
				a=nband(a, all32mask)
				b=nband(b, all32mask)
				local ret = fix_sign_32(nbxor(a, b))
				return ret
			end
			
			--[[
			mybit.lshift = function(a,b)
				if a<0 then a=nband(nbnot(-a)+1, all32mask) end
				if b>15 then
					local ret = mybit.lshift(mybit.lshift(a, b-15), 15)
					return ret
				end
				local ret = fix_sign_32(nbit.lshift(a, b))
				return ret
			end
			mybit.rshift = function(a,b)
				if a<0 then a=nband(nbnot(-a)+1, all32mask) end
				local ret = fix_sign_32(nbit.rshift(a, b))
				return ret
			end
			--]]

			return mybit
		end
	end
end
error('No compatible bit library found')
