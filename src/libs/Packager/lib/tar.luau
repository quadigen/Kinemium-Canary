--!strict
--!optimize 2
--!native

local tar = {};

local function spanstring(buf: buffer, offset: number, max: number): string
    return buffer.readstring(
        buf,
        offset,
        math.min(
            (zune.mem.findScalarPos(buf, offset, 0) or offset + max) - offset,
            max
        )
    );
end

function tar.read(buf: buffer): { [string]: buffer }
    local len: number = buffer.len(buf);
    local offset: number = 0;
    local files: { [string]: buffer } = {};
    local links: { [string]: string } = {};
    
    while (offset + 512 <= len) do
        local name = spanstring(buf, offset, 100);
        if (#name == 0) then
            break;
        end

        local flag = buffer.readu8(buf, offset + 156);
        local size_str = spanstring(buf, offset + 124, 12);
        local size = tonumber(size_str, 8) or 0;

        if (flag == 50) then -- symlink
            local linkname = spanstring(buf, offset + 157, 100);
            links[name] = linkname;
            offset += 512;
            continue;
        elseif (flag == 0 or flag == 48) then -- file
            local data_offset = offset + 512
            if (data_offset + size > len) then
                break;
            end
            local data = buffer.create(size);
            buffer.copy(data, 0, buf, data_offset, size);
            files[name] = data;
        end
        -- unknown
        local padded = math.ceil(size / 512) * 512;
        offset += 512 + padded;
    end

    for link, target in links do
        local parent = zune.fs.path.dirname(link) or "";
        local target_path = zune.fs.path.resolve(parent, target);
        if (files[target_path]) then
            files[link] = files[target_path];
        end
    end

    return files;
end

return tar;
