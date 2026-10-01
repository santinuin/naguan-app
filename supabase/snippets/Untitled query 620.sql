
select b.position as bloque, b.type, i.round as vuelta, i.position as orden,
       coalesce(e.name, 'ENFRIÁ') as que, i.side, i.duration_s, i.reps
from program p
join program_session ps on ps.program_id = p.id
join block b            on b.session_id  = ps.session_id
join block_item i       on i.block_id    = b.id
left join exercise e    on e.id          = i.exercise_id
where p.slug = 'unbreakable' and ps.position = 1
order by b.position, i.round, i.position;