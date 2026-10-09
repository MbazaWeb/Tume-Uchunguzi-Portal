-- Prevent authenticated citizens from changing their own profile role.
-- Service-role operations and already-authorized administrators may assign roles.
CREATE OR REPLACE FUNCTION public.guard_profile_role_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  actor_role text;
BEGIN
  IF NEW.role IS NOT DISTINCT FROM OLD.role THEN
    RETURN NEW;
  END IF;

  IF COALESCE(auth.role(), '') = 'service_role' THEN
    RETURN NEW;
  END IF;

  SELECT p.role::text
    INTO actor_role
    FROM public.profiles AS p
   WHERE p.id = auth.uid();

  IF actor_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'Only an authorized administrator may change account roles'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.guard_profile_role_change() FROM PUBLIC;

DROP TRIGGER IF EXISTS profiles_role_change_guard ON public.profiles;
CREATE TRIGGER profiles_role_change_guard
BEFORE UPDATE OF role ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.guard_profile_role_change();
