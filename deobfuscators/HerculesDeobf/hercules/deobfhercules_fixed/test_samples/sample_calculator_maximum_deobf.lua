local v0 = string["char"]
local v1 = table["concat"]
local v2 = table["insert"]

local fn_main_P1 = function(...)
        local v0 = print
        local fn_main_P1_P0 = function(...)
                    local v0 = (a1 + a2)
                    return (a1 + a2)
        end
        local v1 = 2
        local v2 = 3
        print(fn_main_P1_P0(2, 3))
        return
end
fn_main_P1()
local fn_main_P2 = function(...)
        local v0 = print
        local fn_main_P2_P0 = function(...)
                    local v0 = (a1 * a2)
                    return (a1 * a2)
        end
        local v1 = 4
        local v2 = 5
        print(fn_main_P2_P0(4, 5))
        return
end
fn_main_P2()
local fn_main_P3 = function(...)
        local v0 = print
        local fn_main_P3_P0 = function(...)
                    local v0 = (a1 + a2)
                    return (a1 + a2)
        end
        local v1 = 10
        local fn_main_P3_P1 = function(...)
                    local v0 = (a1 * a2)
                    return (a1 * a2)
        end
        local v2 = 2
        local v3 = 3
        print(fn_main_P3_P0(10, fn_main_P3_P1(2, 3)))
        return
end
fn_main_P3()
return
