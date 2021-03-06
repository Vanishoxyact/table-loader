--v [NO_CHECK] function(path: string) --> map<string, WHATEVER>
function read_file(path)
    local configEnv = {}
    local f,err = loadfile(path);
    if f then
        --local local_env = getfenv(1);
        setfenv(f, configEnv);
        package.loaded[f] = true;
        f();
        for i, v in pairs(configEnv) do
            out(tostring(i) .. " " .. tostring(v));
        end
        return configEnv;
    else
        out(err);
        return nil;
    end
end

--v function(schema: vector<string>, data: vector<vector<string>>, keyIndex: number) --> map<string, map<string, string>>
function convertUniqueKeyDataIntoTable(schema, data, keyIndex)
    local dataTable = {} --: map<string, map<string, string>>
    for _, dataRow in ipairs(data) do
        local tableRow = {} --: map<string, string>
        local rowKey;
        for i, dataValue in ipairs(dataRow) do
            if i == keyIndex then
                rowKey = dataValue;
            else
                tableRow[schema[i]] = dataValue;
            end
        end
        dataTable[rowKey] = tableRow;        
    end
    return dataTable;
end

--v function(schema: vector<string>, data: vector<vector<string>>, keyIndex: number) --> map<string, vector<map<string, string>>>
function convertListKeyDataIntoTable(schema, data, keyIndex)
    local dataTable = {} --: map<string, vector<map<string, string>>>
    for _, dataRow in ipairs(data) do
        local tableRow = {} --: map<string, string>
        local rowKey;
        for i, dataValue in ipairs(dataRow) do
            if i == keyIndex then
                rowKey = dataValue;
            else
                tableRow[schema[i]] = dataValue;
            end
        end
        local keyRows = dataTable[rowKey];
        if not keyRows then
            keyRows = {};
            dataTable[rowKey] = keyRows;
        end
        table.insert(keyRows, tableRow);
    end
    return dataTable;
end

--v function(completeTable: map<string, WHATEVER>) --> map<string, WHATEVER>
function convertDataIntoTable(completeTable)
    local schema = completeTable["SCHEMA"] --: vector<string>
    local keyData = completeTable["KEY"] --: vector<string>
    local keyIndex;
    for i, schemaEntry in ipairs(schema) do
        if schemaEntry == keyData[1] then
            keyIndex = i;
        end
    end
    out("FOUND KEY AT INDEX:" .. keyIndex);
    local data = completeTable["DATA"] --: vector<vector<string>>
    if keyData[2] == "UNIQUE" then
        out("GENERATING DATA TABLE FOR UNIQUE KEY");
        return convertUniqueKeyDataIntoTable(schema, data, keyIndex);
    else
        out("GENERATING DATA TABLE FOR LIST KEY");        
        return convertListKeyDataIntoTable(schema, data, keyIndex);
    end
end

--v [NO_CHECK] function(input: string, regex: string) --> vector<string>
function gmatchToVector(input, regex)
    local result = {} --: vector<string>
    for match in string.gmatch(input, regex) do
        table.insert(result, match);
    end
    return result;
end

--v function(masterDataTable: map<string, WHATEVER>, newDataTable: map<string, WHATEVER>, keyType: string)
function mergeDataTables(masterDataTable, newDataTable, keyType)
    for key, value in pairs(newDataTable) do
        if keyType == "LIST" then
            --# assume value: vector<map<string, string>>
            local masterTableKeyTable = masterDataTable[key];
            --# assume masterTableKeyTable: vector<map<string, string>>
            if not masterTableKeyTable then
                -- No need to merge vectors as not in master
                masterDataTable[key] = value;
            else
                -- Merge new vector into master table
                for i, newTableVectorValue in ipairs(value) do
                    table.insert(masterTableKeyTable, newTableVectorValue);
                end
            end
        else
            -- Replace value in master table
            masterDataTable[key] = value;
        end
    end
end

-- --v function(masterTable: map<string, WHATEVER>, newTable: map<string, WHATEVER>) --> boolean
-- function validateTableSchemas(masterTable, newTable)
--     for key, value in pairs(masterTable) do
--         if key == "SCHEMA" or key == "KEY" then
--             --# assume value: vector<string>
--             for i, schemaKeyValue in ipairs(value) do
--                 if not (newTable[key][i] == schemaKeyValue) then
--                     out("Could not merge tables. " .. key .. " lists did not match.");
--                     return false;
--                 end
--             end
--         end
--     end
--     return true;
-- end

function loadTables()
    local game_interface = cm:get_game_interface();

    if not game_interface then
        out("no game_interface");
    else
        out("STARTED LOADING TABLES");
        local file_str_c = game_interface:filesystem_lookup("/script/campaign/tables", "*.lua");
        out("TABLE FILES FOUND:" .. file_str_c);

        local TABLES = {} --: map<string, map<string, WHATEVER>>
        if file_str_c ~= "" then
            local matches = gmatchToVector(file_str_c, '([^,]+)');
            for i, filename in ipairs(matches) do
                out("LOADING TABLES FROM:" .. filename);

                local current_file = filename;
                local pointer = 1;
                
                while true do
                    local next_separator = string.find(current_file, "\\", pointer) or string.find(current_file, "/", pointer);
                    
                    if next_separator then
                        pointer = next_separator + 1;
                    else
                        if pointer > 1 then
                            current_file = string.sub(current_file, pointer);
                        end
                        break;
                    end
                end
                
                local suffix = string.sub(current_file, string.len(current_file) - 3);
                
                if string.lower(suffix) == ".lua" then
                    current_file = string.sub(current_file, 1, string.len(current_file) - 4);
                end

                local fileContent = read_file("tables/" .. current_file);
                for tableName, completeTable in pairs(fileContent) do
                    out("LOADING TABLE:" .. tableName);
                    local convertedTable = convertDataIntoTable(completeTable);
                    if not TABLES[tableName] then
                        TABLES[tableName] = convertedTable;
                    else
                        mergeDataTables(TABLES[tableName], convertedTable, completeTable["KEY"][2]);
                    end
                end
            end
        end
        out("FINISHED LOADING TABLES");

        -- local testDataTable = TABLES["TEST_DATA"] --: map<string, map<string, string>>
        -- out("TEST_DATA");   
        -- out(testDataTable["One"]["value1"]);
        -- out(testDataTable["One"]["value2"]);
        -- out(testDataTable["Two"]["value1"]);
        -- out(testDataTable["Two"]["value2"]);
        -- out(testDataTable["Three"]["value1"]);
        -- out(testDataTable["Three"]["value2"]);

        -- local testDataListTable = TABLES["TEST_DATA_LIST"] --: map<string, vector<map<string, string>>>
        -- out("TEST_DATA_LIST ONE");    
        -- local testDataOneRows = testDataListTable["One"];
        -- for i, datarow in ipairs(testDataOneRows) do
        --     out(datarow["value1"]);
        --     out(datarow["value2"]);
        -- end
        -- out("TEST_DATA_LIST TWO");        
        -- local testDataTwoRows = testDataListTable["Two"];
        -- for i, datarow in ipairs(testDataTwoRows) do
        --     out(datarow["value1"]);
        --     out(datarow["value2"]);
        -- end
        -- out("TEST_DATA_LIST THREE");        
        -- local testDataThreeRows = testDataListTable["Three"];
        -- for i, datarow in ipairs(testDataThreeRows) do
        --     out(datarow["value1"]);
        --     out(datarow["value2"]);
        -- end

        _G.TABLES = TABLES;
    end
end

--" -> \\\"
--(.*?)[\t\r] -> "$1", 
--(.*), \n -> {$1},\n