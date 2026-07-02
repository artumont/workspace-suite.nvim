local utils = require("workspace-suite.utils")

describe("utils", function()
  describe("make_relative", function()
    it("should make a nested path relative to base", function()
      local base = "/a/b/c"
      local target = "/a/b/c/d/e"
      assert.are.equal("d/e", utils.make_relative(base, target))
    end)

    it("should return the target path if not nested in base", function()
      local base = "/a/b/c"
      local target = "/x/y/z"
      assert.are.equal("/x/y/z", utils.make_relative(base, target))
    end)

    it("should return . if base and target are the same", function()
      local base = "/a/b/c"
      local target = "/a/b/c"
      assert.are.equal(".", utils.make_relative(base, target))
    end)
  end)

  describe("json read and write", function()
    it("should write and read JSON tables correctly", function()
      local temp_file = os.tmpname()
      local test_data = {
        folders = {
          { path = "foo", name = "Foo" },
          { path = "bar", name = "Bar" }
        },
        settings = {
          foo = "bar"
        }
      }

      local ok, err = utils.write_json(temp_file, test_data)
      assert.is_true(ok)
      assert.is_nil(err)

      local data, read_err = utils.read_json(temp_file)
      assert.is_nil(read_err)
      assert.are.same(test_data, data)

      os.remove(temp_file)
    end)
  end)

  describe("session paths", function()
    it("should return correct session directory and file paths", function()
      local root = "/my/project"
      assert.are.equal("/my/project/.nvim/sessions", utils.session_dir(root))
      assert.are.equal("/my/project/.nvim/sessions/session.json", utils.session_file(root))
    end)
  end)
end)
