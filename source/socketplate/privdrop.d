/++
    Privilege dropping
 +/
module socketplate.privdrop;

import std.typecons : nullable, Nullable;

@safe nothrow:

version (Posix) {
    public import core.sys.posix.sys.types : uid_t, gid_t;

    ///
    struct Privileges {
        Nullable!uid_t user; ///
        Nullable!gid_t group; ///

        ///
        static bool resolve(string username, string groupname, out Privileges result) {
            result = Privileges();

            uid_t uid;
            gid_t gid;

            if (!resolveUsername(username, uid)) {
                return false;
            }

            if (!resolveGroupname(groupname, gid)) {
                return false;
            }

            result.user = uid;
            result.group = gid;

            return true;
        }
    }

    ///
    Privileges currentPrivileges() @nogc {
        import core.sys.posix.unistd;

        return Privileges(
            nullable(getuid()),
            nullable(getgid()),
        );
    }

    ///
    bool resolveUsername(string username, out uid_t result) @trusted {
        import core.sys.posix.pwd;
        import std.conv : to;
        import std.string : fromStringz;

        bool usernameCouldBeUid = true;
        uid_t usernameNumeric;
        try {
            usernameNumeric = username.to!uid_t();
        } catch (Exception) {
            usernameCouldBeUid = false;
        }

        scope (exit) {
            endpwent();
        }

        for (passwd* db = getpwent(); db !is null; db = getpwent()) {
            if (db.pw_name.fromStringz != username) {
                if (!usernameCouldBeUid) {
                    continue;
                }

                if (db.pw_uid != usernameNumeric) {
                    continue;
                }
            }

            result = db.pw_uid;
            return true;
        }

        return false;
    }

    ///
    bool resolveGroupname(string groupname, out gid_t result) @trusted {
        import core.sys.posix.grp;
        import std.conv : to;
        import std.string : toStringz;

        group* g = getgrnam(groupname.toStringz);
        if (g is null) {
            gid_t groupnameNumeric;
            try {
                groupnameNumeric = groupname.to!gid_t;
            } catch (Exception) {
                return false;
            }

            g = getgrgid(groupnameNumeric);

            if (g is null) {
                return false;
            }
        }

        result = g.gr_gid;
        return true;
    }

    ///
    bool dropPrivileges(Privileges privileges) @nogc {
        if (!privileges.group.isNull) {
            if (!dropGroup(privileges.group.get)) {
                return false;
            }
        }

        if (!privileges.user.isNull) {
            if (!dropUser(privileges.user.get)) {
                return false;
            }
        }

        return true;
    }

    private @nogc {
        bool dropUser(uid_t uid) @trusted {
            import core.sys.posix.unistd : setuid;

            return (setuid(uid) == 0);
        }

        bool dropGroup(gid_t uid) @trusted {
            import core.sys.posix.unistd : setgid;

            return (setgid(uid) == 0);
        }
    }
}
